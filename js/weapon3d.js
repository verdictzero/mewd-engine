/* =====================================================================
   MEWD — the thing in your hands
   =====================================================================

   FOUR MODELS NOW, and this file used to be certain there was one.
   Three are somebody else's, dropped in as they stand: the
   flamethrower the user built was replaced by one of Vaportrash's, at
   the user's request, and the extinguisher and the cerebral bore came
   from there too. The fourth, the minigun, is the user's own again, and
   carries its own nozzle and a barrel set that turns — see GUNS.
   All are .glb, all are drawn in the same little scene
   in front of the world, and that scene has its own perspective camera
   sitting at the origin looking down -z with the gun parked in front of
   it in metres — so "where the gun is on screen" is the handful of
   numbers in VIEW below, and nothing about the level or the player's
   position enters into it.

   BOTH ARE LOADED AT START AND ONE IS VISIBLE. Swapping weapons hides a
   group and shows another, which costs nothing; loading on the switch
   would cost a hitch in the middle of the one moment the player is
   asking for something to happen.

   IT IS DRAWN INTO THE SAME LOW-RES BUFFER as the world, after it and
   over it, with depth cleared in between so the barrel never pokes
   through a wall you are standing against. That buffer is what keeps a
   1024-pixel painted diffuse honest: at three hundred rows the texels
   are chunky again, and the palette snap eats the gun along with the
   floor.

   HEAVILY LOW AND RIGHT, as asked — the body of the gun is off the
   bottom of the frame and the barrel comes in across the lower right
   quarter, the way it is drawn in every game that got this right. What
   is on screen is the end that matters: the nozzle, whatever is burning
   under it, and what comes out.

   WHERE THE NOZZLE IS, AND HOW IT WAS FOUND. It used to be two ways:
   the old flamethrower carried marker spheres, put there in Blender by
   the user and baked into the file's extras by tools/prep-model.mjs,
   and everything else said so in GUNS below. There is only the second
   way now, because there is no longer a model in the game that the
   user made: the standing rule since the van is that somebody else's
   file is not rewritten on the way in, so the anchors are numbers in
   GUNS, in the MODEL'S own units — the game saying where it intends to
   point rather than the game editing the asset. The reader they are
   read back through (asset.extras.anchors) is kept, because a model
   that does carry markers is still handled.

   AND THE NUMBERS WERE MEASURED OFF PICTURES. A gun with no markers has
   to be looked at: the new flamethrower was drawn flat from its left,
   from above and straight down the barrel, over a grid ruled in the
   model's own units, with candidate points crossed on it and moved
   until they sat where they belong. That is how [0, 3.9, 24.3] and
   [0, 3.0, 25.7] below came to be — the centre of the bore inside the
   C-shaped muzzle bracket, and the lip of the little gold igniter pipe
   that runs under the barrel and turns up in front of it. Reading the
   bounding box of a part would have put the first of them inside the
   metal and the second on the wrong tube.

   AND ONE OF THEM HAD TO BE RESIZED, which is the other thing a file
   somebody else made will do to you. The flamethrower is 1.4 units nose
   to tail and centred on its own origin; the extinguisher is 4.7 units
   long and stands on that origin like a model on a table. `fit` scales a
   model to the game's length and recentres it on its own bounding box,
   and the anchor goes through the same transform, so a gun either
   arrives in this scene's frame already or says what to do about it.
   ===================================================================== */

import * as THREE from 'three';
import { loadGLB } from './glb.js';
import { Pix } from './pixel.js';

/* How long a gun is in this scene, in metres, measured off the
   flamethrower — which is the one VIEW was tuned against, so it is the
   ruler whether or not it is a round number. */
export const GUN_LENGTH = 1.4;

/* THE GUNS, keyed by the weapon that holds them.

     url     the model
     fit     scale it to this length and centre it on its own box. Absent
             means the model is already in this scene's frame, which is
             true of exactly one of them and only because it was made for
             it
     out     how far in front of the eye it is held, as a multiple of
             VIEW.pos's z, which is how much of the gun's LENGTH is on
             screen: at 1 the back quarter of a gun is behind the eye and
             what you see is the front half, filling the corner; at 3 the
             whole thing is in front of you and reads end to end. Absent
             means 1
     nozzle  where the business end is, in the MODEL'S own units. Absent
             means the file says so itself, in asset.extras.anchors
     pilot   a small flame that is always alight, on the same terms.
             A gun that does not burn anything does not have one
     tint    what the muzzle effect is coloured, and `cold` whether the
             frames are desaturated first. The two weapons use the same
             twenty frames of billowing and differ by those two: one is
             fire as painted, one is the white-blue of something very
             cold leaving a nozzle very fast
     muzzle  how long and wide that effect is, in metres
     pos     a gun's own offset on VIEW.pos, in metres, for one that is
             carried somewhere other than where a hose is. Absent means
             none
     rot     and its own turn on VIEW's, pitch yaw roll, for the same
             reason. Absent means none
     heat    the material that glows with use, the run of the barrels
             along it, and WHICH NUMBER ON THE PLAYER it reads — see
             GUN_FRAG. Two guns have one and they must not share a
             number, or a minigun put away hot hands its glow to
             whatever is drawn next
     spin    turns a second the part the file names as rotating makes
             at full speed. Only the minigun has one
     display a material the file paints flat, which is a SCREEN: it gets
             the live feed and the gauges instead of the gun shader —
             see js/scope.js — or the thermal feed, js/thermal.js. The
             lance has one, and so does the launcher
     optics  and a material that is a LENS, for the same reason
     aim     a SECOND hold, for a gun that is raised to the eye rather
             than carried at the hip: its own pos, rot and out, blended
             to by Weapon3D.aim. The lance has one, and so does the
             launcher, because both have something on them worth
             putting your eye to
     paint   'vertex' for a model whose colour is in its VERTICES rather
             than in a texture — a sculpt, painted where it was modelled,
             shipped straight out of tools/decimate-model.mjs. A texture
             in the file wins over it. No gun in the rack uses it now:
             the first launcher did until it was baked
     screen  a screen the game BUILDS, for a gun whose file has a flat
             face where a screen should be and no mesh to put one on:
             [x0, y0, x1, y1, z] in the model's own units, a quad facing
             the eye at that depth. It wears whatever screen the gun's
             scope makes, exactly as `display` does. No gun uses it now:
             the first launcher did, and the XM222 has its own display
     tubes   more than one mouth, for a gun that has more than one: each
             in the model's own units, like `nozzle`. What leaves them is
             the world's business; Weapon3D.tubeWorld hands each one
             over the way nozzleWorld hands over the one
     loaded  the rounds in those mouths, for a gun whose file has them
             as parts: { prefix, ammo } — the parts are prefix0, prefix1,
             ... in firing order, and only as many as the player has of
             that ammo are drawn, the last ones. The launcher's rockets */
export const GUNS = {
  /* THE CEREBRAL BORE, the user's third model and the one with nothing
     coming out of the nozzle but a red line: the projectile is the
     world's business (js/bore.js) and the sight is drawn from the point
     nozzleWorld hands over. Stripped of its normal and metal-rough maps
     by tools/prep-model.mjs, which is the same treatment the
     flamethrower got and half of what it weighed. */
  BORE: {
    url: 'assets/models/bore.glb',
    /* A THIRD SMALLER AND A THIRD FARTHER OFF than the other two, at
       the user's request: the launcher is a big square thing, and at
       the flamethrower's size and distance it was a quarter of the
       picture. `fit` is the size. `out` multiplies how far in front of
       the eye it is held — z alone, a push straight back along the
       view, which is what holding a thing farther from your face is.
       The first try scaled the whole position, along the line from the
       eye, on the theory that a point moved along that line keeps its
       place on screen; it does, but the place it kept was the gun's
       CENTRE, which sits below the bottom of the frame by design, so
       the gun shrank around a point you cannot see and all but left the
       picture. Pushed straight back it recedes toward the middle of the
       screen the way anything farther off does, and stays in its
       corner. The two numbers together halve it on screen. See update(). */
    fit: GUN_LENGTH * 0.67,
    out: 1.33,
    /* the mouth of the launcher, off the model's own vertices: the
       furthest along +z are at 34.7 and sit a little under the centre
       line, so this is just past them and on it */
    nozzle: [0, -4, 37],
    pilot: null,
    /* what leaves the launcher: a short red exhaust, not a flame —
       scaled with the launcher, since it hangs off the model's group
       in metres and not off the model */
    tint: [1.6, 0.30, 0.22],
    muzzle: { len: 0.094, wid: 0.067 },
  },
  /* THE FLAMETHROWER, the user's second: a Sketchfab model of
     Vaportrash's, in place of the one the user built, at the user's
     request. Seventeen meshes on one painted sheet, forty-six units
     nose to tail with the barrel along +z, and no markers in it — see
     the note above for how its two anchors were found.

     HELD THREE TIMES AS FAR OUT as the old one was, at the user's
     request, because this gun is worth looking at and at arm's length
     you saw a red bottle and nothing else: a quarter of its length was
     behind the eye and the rest was too close to read. At three the
     whole weapon is in front of you — muzzle, bottles, receiver, grip —
     and the bottle that used to fill the corner is a third of what it
     was. */
  FLAMER: {
    url: 'assets/models/flamethrower.glb',
    fit: GUN_LENGTH,
    out: 3.0,
    /* the centre of the bore, a little past the front of the muzzle
       bracket, so the stream is born outside the metal */
    nozzle: [0, 3.9, 24.3],
    /* and the lip of the igniter pipe below it, which reaches further
       forward than the barrel does — the same arrangement the old gun
       had, and the reason a flamethrower has a small flame burning on
       it when the trigger is up */
    pilot: [0, 3.0, 25.7],
    tint: [1, 1, 1],
    muzzle: { len: 0.34, wid: 0.14 },
  },
  /* AND THE EXTINGUISHER RIFLE, held nearly as far out and for the same
     reason: it is a fire extinguisher with a stock on it and the joke
     only lands if you can see the whole of it. */
  EXTINGUISHER: {
    url: 'assets/models/extinguisher.glb',
    fit: GUN_LENGTH,
    out: 2.8,
    /* the tip of the barrel, measured off the model's own vertices: the
       forty furthest along +z average to (0, 0.76, 2.16) and this is a
       little past them, so the plume starts outside the metal */
    nozzle: [0, 0.78, 2.20],
    pilot: null,
    tint: [0.72, 1.02, 1.45],
    cold: true,
    muzzle: { len: 0.30, wid: 0.22 },
  },
  /* THE MINIGUN, the user's fourth model and the first since the old
     flamethrower to carry its own answers: a marker cylinder named for
     the emission point, which tools/prep-model.mjs takes out of the
     mesh and writes into the file's extras as the nozzle, and a barrel
     set named to be ROTATED, which it leaves in and names in the same
     place (extras.spin). So `nozzle` is null here — the file says — and
     the game's part is how it is held and what happens to it in use.

     IN THE CORNER, the user's pick of the six placements that were
     drawn up for it (see README, THE MINIGUN, for the other five and
     what each looked like): held on VIEW's own hold like the streams
     are, a quarter longer than the flamethrower and a little nearer
     than it, so the receiver fills the corner and the barrel set comes
     in across the lower right quarter of the picture. Any of the
     others is a `pos` and a `rot` on this entry and a change to these
     two numbers.

     `heat` is the barrel material and the run of the barrels along it,
     in the model's own units: the shader tints that material from the
     muzzle back as the gun is used (see GUN_FRAG), dull red first,
     orange, and then the yellow-white of steel that should have
     stopped. `spin` is how many turns a second the barrel set makes at
     full speed. */
  MINIGUN: {
    url: 'assets/models/minigun.glb',
    fit: GUN_LENGTH * 1.25,
    out: 2.6,
    nozzle: null,
    pilot: null,
    /* what leaves the muzzle: a short hard flash rather than a tongue,
       the frames desaturated and pushed toward white-yellow */
    tint: [1.7, 1.4, 0.8],
    cold: true,
    muzzle: { len: 0.34, wid: 0.30, additive: true },
    /* NO DISC ACROSS THE MUZZLE, any more, at the user's request: the
       flash that faced the eye is gone, and the tracers — which now
       start at the end of the barrel and are very long — are what
       says the gun is firing. See js/tracers.js. */
    heat: { material: 'minigun_barrel_mat', z: [-0.83, 10.56], from: 'heat' },
    spin: 6,
  },

  /* THE WZBR-1 POSITRON SNIPER LANCE, the user's fifth model and the
     first one with a SCREEN in it.

     Vaportrash's again, and this one carries its own answers the way
     the minigun did — not as marker spheres but as NAMED MESHES. Four
     meshes on three materials: `wzbr_mat`, the painted metal, over
     seventy thousand vertices of receiver and barrel; `optics_mat`, a
     fifty-millimetre lens up front, painted flat green; and
     `dynamic_display_surface_mat`, a panel eighty millimetres across on
     the rear deck facing straight back at whoever is holding it, painted
     flat near-black. A modeller does not name a node
     `dynamic_display_surface_1` by accident. See js/scope.js for what
     goes on it.

     THE LONGEST THING IN THE RACK by half again — two and a half metres
     of gun, and `fit` keeps it that — and HELD THE FURTHEST OUT, which
     is not vanity. The panel sits at the BACK of the model; the back of
     a two-and-a-half-metre weapon held where a hose is held is inside
     the near plane and across the whole picture. Pushed out it recedes
     to where a monitor on a gun should be: readable, in the upper left
     of the corner the gun fills, with the barrel running away from it
     to the muzzle. `pos` then slides the whole thing left and down so
     the screen clears the middle of the frame rather than sitting in
     it, and `rot` cants it a few degrees so you are looking at the
     panel rather than across it.

     IT HAS NO `heat`, and it used to. The whole chassis glowed with the
     coil, from the middle out, on GUN_FRAG's second gradient mode — the
     mode exists for this gun and this gun is the only thing that ever
     asked for it. At the user's request the lance does not heat at all
     any more, so the entry is gone and the mode is left where it is:
     one branch behind `if (heat > 0.001)`, which nothing on this weapon
     now satisfies, and which the next gun that heats from its middle
     will find already written and already correct.

     The muzzle effect is small and additive and green-white — the thing
     that says this gun is firing is the beam, which is js/beam.js's, and
     this is only the bloom where it leaves the metal. */
  LANCE: {
    url: 'assets/models/lance.glb',
    fit: GUN_LENGTH * 1.9,
    out: 2.4,
    pos: [-0.12, 0.23, 0],
    rot: [0.03, -0.09, 0.06],
    /* the mouth of the bore, off the model's own vertices: the twenty
       furthest along +z average to (-0.002, 0.018, 1.588) and this is a
       little past them and on the centre of them */
    nozzle: [0, 0.018, 1.63],
    pilot: null,
    tint: [0.55, 1.35, 0.80],
    cold: true,
    muzzle: { len: 0.46, wid: 0.26, additive: true },
    /* AND THE HOLD IT COMES TO WHEN YOU PUT YOUR EYE TO IT, at the
       user's request — see the head of js/scope.js for why the zoom
       moves the WEAPON rather than the picture. The gun swings up and
       inboard until the panel on its rear deck is in the middle of the
       frame and a hand's breadth from the eye, and the turn cancels
       VIEW's own cant so you are looking at the screen square on rather
       than across it. `out` pulls it in: the whole gun is nearer,
       because you have brought it to you.

       THESE FOUR NUMBERS WERE SOLVED, not nudged. With the panel's own
       corners projected through the weapon camera, both its position
       and its size on screen go exactly as 1/d, and d is linear in
       `out` — measured d = 0.330*out - 0.481 over four settings, and
       the panel's height in clip units is 0.1333/d to four places. So
       out = 1.80 puts the screen 0.113 from the eye and 1.18 clip units
       tall, which is 59% of the picture's height and about square: a
       scope you look INTO, not a postage stamp on a rifle. Position is
       linear in pos at a fixed out (the push is along the eye ray, so
       it cannot change d), which makes the centring a two-line solve —
       9.18 clip units per unit of pos.x, 14.71 per unit of pos.y — and
       these are its answer, to the pixel. */
    aim: { pos: [-0.1894, 0.2730, 0], rot: [-0.04, -0.17, 0.05], out: 1.80 },
    display: { material: 'dynamic_display_surface_mat' },
    optics: { material: 'optics_mat', base: [0.34, 0.80, 0.0] },
  },

  /* THE QUAD LAUNCHER, the XM222: the user's sixth slot, and the
     second model to fill it. The first was a Nomad sculpt, remeshed and
     baked by tools/decimate-model.mjs and tools/bake-model.mjs, with a
     screen the game had to build on a blank face of its sight. This one
     came modelled and textured, with the screen already in it: a
     slightly domed panel on the back of the sight, under its own
     material — which the file spells `dyanmic_display_surface_mat`, and
     so does this table — prepared by the user for the thermal feed to
     be drawn on. So it is the lance's case, `display`, not `screen`.

     Prepared by tools/blender/prep_launcher.py: the file's node
     transforms baked into its vertices, half a turn so the rockets'
     noses point +z like every other gun's muzzle, the two colour sheets
     cut to 1024 and the normal, metal-rough and specular maps dropped,
     and the ordnance — one mesh of four rockets — split into four named
     rocket_0 to rocket_3 in the order the tubes fire, so `loaded` can
     draw a tube empty once its rocket has gone. Fourteen megabytes to
     under one.

     FOUR TUBES IN A GREEN BOX, a trigger guard under its front third
     and the sight on the left of the front, looking back at the eye.
     The numbers are off the vertices:

       the four rocket noses stand a little proud of the front face, at
       z = 3.299, centred on x = +-0.44 and y = 1.395 and 0.605. `tubes`
       is those four, in the order they fire — top left, top right,
       bottom left, bottom right, as the gunner sees them, since the
       half turn puts the model's +x on the left.

       the screen runs 1.271 to 1.999 across and 0.824 to 1.565 up, and
       bulges toward the eye from z = 1.475 at its rim to 1.377 at its
       middle. Very nearly square: see THERMAL_ASPECT in js/thermal.js. */
  LAUNCHER: {
    url: 'assets/models/launcher.glb',
    /* long and narrow where the last one was a box, so a little over
       the flamethrower's length to have the tubes a hand apart; held
       low on the right, running away into the middle, with the sight's
       screen on its near front corner showing what it sees — picked in
       the running game off three holds side by side */
    fit: GUN_LENGTH * 1.05,
    out: 2.6,
    pos: [0.20, -0.15, 0],
    rot: [0.05, 0.16, -0.03],
    nozzle: [0.0, 1.0, 3.299],
    tubes: [[0.442, 1.395, 3.299], [-0.438, 1.395, 3.299], [0.438, 0.605, 3.299], [-0.442, 0.605, 3.299]],
    pilot: null,
    /* what leaves a tube: the motor lighting, short and hot, off the
       same frames as everything else, whitened and warmed */
    tint: [1.8, 1.25, 0.7],
    cold: true,
    muzzle: { len: 0.30, wid: 0.22, additive: true },
    display: { material: 'dyanmic_display_surface_mat' },
    /* the rockets in the tubes, by name, in firing order, and the ammo
       they stand for: a tube is drawn empty once its rocket has gone */
    loaded: { prefix: 'rocket_', ammo: 'rockets' },
    /* AND THE HOLD AT THE EYE, SOLVED as the last one's was: `rot`
       cancels VIEW's own pitch, yaw and roll, so the group is square to
       the camera and the screen faces the eye exactly, and `pos` puts
       the screen's middle straight ahead of it at the distance where it
       is about half the picture's height. See the suite. */
    aim: { pos: [-0.1034, 0.2552, 0.4515], rot: [-0.04, -0.17, 0.05], out: 1.0 },
  },
  /* THE ARC MAW, the user's seventh model and the second sculpt: a
     Nomad file of ninety-one thousand triangles whose paint was a white
     sheet and whose whole surface was in a normal map. It was finished
     in Blender, headless, at the user's request: the AO and the
     curvature baked through the normal map, a distressed gunmetal built
     out of nodes on top of them — rust and grime in the cavities, edges
     worn bright, scratches — and baked to a sheet; then cut to sixteen
     thousand triangles with its UVs kept, and the sheet given the AO and
     the relief multiplied into it, because this shader reads colour and
     nothing else. See THE ARC MAW in README.txt.

     THREE PRONGS AT THE FRONT and a loop at the back, and the business
     end is the space between the prongs: `nozzle` is its middle, where
     the bolt leaves and where `orb` — the charge, a ball of blue energy
     with more energy streaming into it — is hung. */
  ARC: {
    url: 'assets/models/arcgun.glb',
    fit: GUN_LENGTH * 1.05,
    /* the prongs reaching into the lower right of the picture with the
       maw a sixth of the way right of the middle and a fifth of the way
       down — picked in the running game off a scan of holds, by where
       the maw lands on screen */
    out: 1.7,
    pos: [0.02, 0.12, 0],
    rot: [0, 0.06, 0],
    nozzle: [0.0, 0.0, 5.42],
    pilot: null,
    /* the discharge's flash at the maw: short, white-blue */
    tint: [0.7, 0.95, 1.9],
    cold: true,
    muzzle: { len: 0.22, wid: 0.22, additive: true },
    /* the ball at full charge, and how far out the energy is gathered
       from, both in metres */
    orb: { radius: 0.11, reach: 0.26, motes: 64 },
  },
};

/* Where the gun sits in front of the eye, in metres, and how it is
   turned. Both models' barrels run along +z; the camera looks down -z;
   so it is turned half a circle and then a touch inward so the barrel
   points at the middle of the picture rather than parallel to it. */
export const VIEW = {
  pos: [0.33, -0.40, -0.33],
  yaw: 0.17, pitch: 0.04, roll: -0.05,
  fov: 62,
};

/* Game units to a metre of gun, when a point in this scene has to be
   handed to the world. The nozzle is projected as a RAY — a point
   scaled along the line from the eye keeps its place on screen
   whatever this number is — so it only decides how far in front of the
   eye the stream is born, and forty puts it a little past arm's reach
   and clear of the near plane. */
export const UNITS_PER_METRE = 40;

/* AND THE FURTHEST INTO THE WORLD THAT POINT MAY EVER BE, which is a
   cap and not a distance. A gun held further out (see `out`) is drawn
   further from the eye, so its nozzle is further along the ray, so the
   stream would be born deeper into the level — and at three times out
   that is seventy units in front of a player whose own radius is
   sixteen, which is the far side of a shelf you are standing against.
   How far a gun is DRAWN is a question about the picture; where its
   fire starts is a question about the level, and the two stopped being
   the same question the moment the guns moved. Forty-six is what the
   longest-reaching of them measured before any of this, so nothing
   about the world changed on the day the picture did. */
export const NOZZLE_REACH = 46;

const GUN_VERT = /* glsl */`
varying vec2 vUv;
varying vec3 vN;
varying vec3 vP;
varying vec3 vL;
#ifdef PAINT
  /* the colour the sculptor painted, per vertex — three declares the
     attribute itself once the material says vertexColors */
  varying vec3 vPaint;
#endif
void main() {
  vUv = uv;
  #ifdef PAINT
    vPaint = color;
  #endif
  vN = normalize(normalMatrix * normal);
  vec4 mv = modelViewMatrix * vec4(position, 1.0);
  vP = mv.xyz;
  vL = position;
  gl_Position = projectionMatrix * mv;
}
`;

/* Painted diffuse, a single fixed key light banded into twelve steps so
   it reads as the same kind of light as the walls, and two warm glows:
   the pilot, small and steady, and the muzzle, big and only while
   firing. No world lighting reaches the gun — a held object is lit by
   whatever is nearest, and what is nearest is its own flame. */
const GUN_FRAG = /* glsl */`
uniform sampler2D map;
uniform float glow;
uniform vec3  glowPos;
uniform float pilot;
uniform vec3  pilotPos;
uniform float dim;
uniform float heat;
uniform vec2  heatZ;
uniform float heatMid;
uniform float heatMode;
varying vec2 vUv;
varying vec3 vN;
varying vec3 vP;
varying vec3 vL;
#ifdef PAINT
  varying vec3 vPaint;
#endif
void main() {
  /* A PAINTED MODEL HAS NO PICTURE TO SAMPLE: its colour arrives in the
     vertices, already linear (glTF says so), which is what an sRGB
     texture is decoded to on the way out of texture2D — so the two
     paths land in the same space and everything below serves both. */
  #ifdef PAINT
    vec4 t = vec4(vPaint, 1.0);
  #else
    vec4 t = texture2D(map, vUv);
    if (t.a < 0.5) discard;
  #endif
  vec3 N = normalize(vN);
  vec3 L = normalize(vec3(-0.35, 0.85, 0.40));
  float d = max(0.0, dot(N, L));
  float l = (0.50 + 0.50 * d) * dim;
  l = floor(l * 12.0 + 0.5) / 12.0;
  vec3 c = t.rgb * l;
  /* THE BARRELS HEAT UP. heat is 0..1 and only ever set on the one
     material the gun's table names (see GUNS[].heat); heatZ is the
     run of the barrels in the mesh's own units, muzzle end last, and
     the glow climbs from the muzzle back down them as the heat rises
     — dull red first, then orange, then the yellow-white of steel that
     should have stopped. Banded like the light above, so it reads as
     the same kind of picture as the rest of the gun. */
  if (heat > 0.001) {
    float along = clamp((vL.z - heatZ.x) / max(heatZ.y - heatZ.x, 1e-4), 0.0, 1.0);
    /* TWO WAYS OF BEING HOT, and the difference is where the energy is.

       A minigun heats at the MUZZLE, because that is where the rounds
       are going off, and the glow creeps back down the barrels from
       there — which is heatMode 0, and the ramp for it is "along".

       A positron lance heats in the MIDDLE, because the coil is in the
       middle, and the glow spreads out from it toward both the muzzle
       and the stock — heatMode 1, at the user's request. "reach" is one
       at the coil and falls away in both directions, so at a low heat
       only the body of the gun is dull red and at a high one the whole
       thing is white, which is a gun about to go off in your hands. */
    float reach = along;
    if (heatMode > 0.5) {
      float half_ = max(max(heatMid - heatZ.x, heatZ.y - heatMid), 1e-4);
      reach = 1.0 - clamp(abs(vL.z - heatMid) / half_, 0.0, 1.0);
    }
    float h = heat * smoothstep(0.0, 0.9, reach * 0.7 + heat * 0.3);
    h = floor(h * 8.0 + 0.5) / 8.0;
    vec3 hot = h < 0.5 ? mix(vec3(0.42, 0.02, 0.0), vec3(1.0, 0.36, 0.05), h * 2.0)
                       : mix(vec3(1.0, 0.36, 0.05), vec3(1.0, 0.92, 0.62), (h - 0.5) * 2.0);
    c = mix(c, hot, h * 0.85) + hot * h * 0.35;
  }
  vec3 fire = vec3(1.0, 0.55, 0.20);
  vec3 tg = glowPos - vP;
  float gd = length(tg);
  float ga = clamp(1.0 - gd / 0.8, 0.0, 1.0);
  ga *= ga;
  float gn = 0.35 + 0.65 * max(0.0, dot(N, tg / max(gd, 1e-4)));
  c += t.rgb * fire * ga * gn * glow * 1.7;
  vec3 tp = pilotPos - vP;
  float pd = length(tp);
  float pa = clamp(1.0 - pd / 0.24, 0.0, 1.0);
  pa *= pa;
  c += t.rgb * fire * pa * pilot;
  gl_FragColor = vec4(c, 1.0);
}
`;

const FLAME_VERT = /* glsl */`
varying vec2 vUv;
void main() { vUv = uv; gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0); }
`;
/* THE SAME FRAMES, TWICE, and the second time they are not fire.
   A tint MULTIPLIES, which is fine for making fire warmer or dimmer and
   useless for making it cold: orange times blue is a muddy olive,
   because there is no blue in the picture to keep. So `desat` takes the
   frame's LUMINANCE first — its shape, with its colour thrown away —
   and the tint then says what colour that shape is. At 0 nothing
   happens and the flamethrower's frames come through as painted; at 1
   the same twenty frames of billowing are a plume of whatever you like,
   which is how one atlas covers both a flame and a jet of CO2. */
const FLAME_FRAG = /* glsl */`
uniform sampler2D map;
uniform float frame;
uniform float frames;
uniform vec3  tint;
uniform float desat;
varying vec2 vUv;
void main() {
  vec4 t = texture2D(map, vec2((vUv.x + frame) / frames, vUv.y));
  if (t.a < 0.5) discard;
  vec3 c = mix(t.rgb, vec3(dot(t.rgb, vec3(0.30, 0.59, 0.11))), desat);
  gl_FragColor = vec4(c * tint, 1.0);
}
`;

function flameMaterial(atlas, additive = false) {
  return new THREE.ShaderMaterial({
    uniforms: { map: { value: atlas.texture }, frame: { value: 0 }, frames: { value: atlas.frames },
                tint: { value: new THREE.Vector3(1, 1, 1) }, desat: { value: 0 } },
    vertexShader: FLAME_VERT, fragmentShader: FLAME_FRAG,
    side: THREE.DoubleSide, depthWrite: false, toneMapped: false, fog: false,
    transparent: additive, blending: additive ? THREE.AdditiveBlending : THREE.NormalBlending,
  });
}

/* A quad lying along +z from the origin: width across x (or y), length
   along z, v running from the base at z=0 to the tip. Two of them
   crossed make a flame that reads from any angle you can see a gun from. */
function tongue(len, wid, vertical) {
  const g = new THREE.BufferGeometry();
  const h = wid / 2;
  const p = vertical
    ? [0, -h, 0,  0, h, 0,  0, h, len,  0, -h, len]
    : [-h, 0, 0,  h, 0, 0,  h, 0, len,  -h, 0, len];
  g.setAttribute('position', new THREE.Float32BufferAttribute(p, 3));
  g.setAttribute('uv', new THREE.Float32BufferAttribute([0, 0, 1, 0, 1, 1, 0, 1], 2));
  g.setIndex([0, 1, 2, 0, 2, 3]);
  return g;
}

export class Weapon3D {
  /** `scope` is js/scope.js's, or null: the thing that owns the lance's
   *  screen and its lens. It is passed in rather than made here because
   *  filling the screen is a render of the WORLD, and every render call
   *  in this game lives in js/main.js.
   *
   *  `scopes` is the same thing for more than one gun — name to scope —
   *  since the launcher has a screen of its own (js/thermal.js) and two
   *  guns cannot share one: a screen is a render target, a camera and a
   *  panel box, and the second gun to load would have moved the first
   *  one's picture. `scope` alone still means the lance's. */
  constructor({ aspect = 1.6, scope = null, scopes = null } = {}) {
    this.scope = scope;
    this.scopes = scopes || (scope ? { LANCE: scope } : {});
    /* HOW FAR THE GUN IS TO THE SHOULDER, 0 at the hip and 1 with your
       eye on the glass. Chased rather than set, so raising the weapon
       is a movement and not a cut — see update(). */
    this.aim = 0;
    this.scene = new THREE.Scene();
    this.camera = new THREE.PerspectiveCamera(VIEW.fov, aspect, 0.02, 12);
    this.guns = {};                  // name -> what load() built
    this.active = null;              // the one on screen
    this.failed = false;
    this.visible = false;
    this.sway = { x: 0, y: 0 };
    this.kick = 0;
    this._tmp = new THREE.Vector3();
    this._tmp2 = new THREE.Vector3();
    this._ndc = new THREE.Vector3();
  }

  /* Whether there is anything to draw. The sprite fallback in the HUD
     turns on when there is not. */
  get ready() { return !!this.gun; }
  /** The gun currently in hand, or null. */
  get gun() { return this.active ? this.guns[this.active] : null; }
  /* kept because the loading screen and the smoke test both ask */
  get loaded() { return Object.keys(this.guns); }

  setAspect(aspect) {
    this.camera.aspect = aspect;
    this.camera.updateProjectionMatrix();
  }

  /** Show one and hide the rest. Unknown, or a weapon whose model never
   *  arrived, leaves whatever was in hand — a missing model is a missing
   *  picture and never a missing weapon. */
  setWeapon(name) {
    if (!this.guns[name] || name === this.active) return;
    for (const [k, g] of Object.entries(this.guns)) g.group.visible = k === name;
    this.active = name;
  }

  /**
   * Every gun in GUNS, into its own group in the one scene.
   *
   * @param atlas  { texture, frames } of flame frames for the pilots and
   *               the muzzle effects
   * @param which  optionally a subset, for a test that wants one
   */
  async load(atlas, which = Object.keys(GUNS)) {
    this.frames = atlas.frames;
    for (const name of which) {
      try {
        this.guns[name] = await this._loadOne(name, GUNS[name], atlas);
      } catch (e) {
        console.warn(`${name} model not available:`, e.message);
      }
    }
    if (!Object.keys(this.guns).length) { this.failed = true; return; }
    for (const g of Object.values(this.guns)) g.group.visible = false;
    this.setWeapon(which.find(n => this.guns[n]));
  }

  async _loadOne(name, def, atlas) {
    /* THIS gun's scope, if it has one — see the constructor */
    const scope = this.scopes[name] || null;
    const paint = def.paint === 'vertex';
    const { root, extras } = await loadGLB(def.url, {
      material: (mdef, maps) => {
        /* TWO OF THE LANCE'S THREE MATERIALS ARE NOT METAL and must not
           go through the gun shader: the file paints them flat — a
           near-black panel and a green disc — because in the original
           they are a screen that was never switched on and a lens that
           was never lit. Here they are both. See js/scope.js.

           This is checked before the `maps.map` fallback below, and has
           to be: neither carries a texture, so without it they would
           both come out of that line as the same flat dark grey and the
           gun would have a hole where its instruments are. */
        const nm = mdef?.name || '';
        if (scope && def.display && nm === def.display.material) return scope.screenMaterial();
        if (scope && def.optics && nm === def.optics.material) return scope.opticsMaterial(def.optics.base);
        /* AND A PAINTED MODEL HAS NO MAP AND IS NOT A HOLE: its colour is
           in the vertices, so the fallback below — which is right for a
           flat-painted part of a textured gun — is wrong for the whole
           of it. It goes through the gun shader like every other gun,
           with the PAINT path on. */
        if (!maps.map && !paint) return new THREE.MeshBasicMaterial({ color: 0x0c1410, toneMapped: false });
        /* and a picture, when the file has one, wins over the paint:
           the vertices only carry the colour when nothing else does */
        const painted = paint && !maps.map;
        const m = new THREE.ShaderMaterial({
          uniforms: {
            map: { value: maps.map || null }, glow: { value: 0 }, glowPos: { value: new THREE.Vector3() },
            pilot: { value: 0.35 }, pilotPos: { value: new THREE.Vector3() }, dim: { value: 1 },
            heat: { value: 0 }, heatZ: { value: new THREE.Vector2(0, 1) },
            heatMid: { value: 0 }, heatMode: { value: 0 },
          },
          vertexShader: GUN_VERT, fragmentShader: GUN_FRAG,
          side: mdef?.doubleSided ? THREE.DoubleSide : THREE.FrontSide, toneMapped: false, fog: false,
          ...(painted ? { defines: { PAINT: '' }, vertexColors: true } : {}),
        });
        /* the file's own name for it, so a table can point at one */
        m.name = mdef?.name || '';
        return m;
      },
    });

    /* --- WHERE THE ANCHORS ARE, and in whose units -------------------
       The file's own if it has them; otherwise this game's table. Either
       way they are in the MODEL's units and go through the same fit
       below, so the two sources cannot disagree about scale. */
    const a = extras.anchors || {};
    const nozzle = def.nozzle || a.nozzle;
    const pilot = def.pilot === null ? null : (def.pilot || a.pilot);
    if (!nozzle) throw new Error('no nozzle anchor, in the file or in GUNS');

    /* --- AND HOW BIG IT IS ------------------------------------------
       `fit` scales the model to the game's gun length along its longest
       axis and recentres it on its own box. The anchors go through the
       same two numbers, which is the whole reason this is done here and
       not by hand in the table: a model swapped for a bigger one moves
       its own nozzle. */
    let scale = 1, centre = new THREE.Vector3();
    if (def.fit) {
      root.updateMatrixWorld(true);
      const box = new THREE.Box3().setFromObject(root);
      const size = box.getSize(new THREE.Vector3());
      scale = def.fit / Math.max(size.x, size.y, size.z);
      box.getCenter(centre);
    }
    const place = p => new THREE.Vector3(p[0], p[1], p[2]).sub(centre).multiplyScalar(scale);

    /* the model, turned barrel-toward -z so it faces the camera's world,
       and scaled and recentred inside a group of its own */
    const inner = new THREE.Group();
    root.scale.setScalar(scale);
    root.position.copy(centre).multiplyScalar(-scale);
    inner.add(root);
    inner.rotation.y = Math.PI;

    const group = new THREE.Group();
    group.add(inner);
    this.scene.add(group);

    /* ONE ENTRY PER MATERIAL, not per mesh. loadGLB builds a material
       once per glTF material and hands the same instance to every
       primitive that names it, and the new flamethrower is seventeen
       meshes sharing one — so without the set, update() would write the
       same three uniforms seventeen times a frame. */
    const gunMaterials = [];
    const seen = new Set();
    let heatMaterial = null;
    root.traverse(o => {
      if (!o.isMesh || !o.material.uniforms?.glow || seen.has(o.material)) return;
      seen.add(o.material);
      gunMaterials.push(o.material);
      /* the one material the barrels wear, if the table names one, is
         the one the heat goes into — see GUN_FRAG */
      if (def.heat && o.material.name === def.heat.material) heatMaterial = o.material;
    });
    if (heatMaterial) {
      heatMaterial.uniforms.heatZ.value.fromArray(def.heat.z);
      /* WHERE THE HOT SPOT IS and which way the glow spreads from it —
         see GUN_FRAG. A gun with no `mid` heats from its muzzle back,
         which is every gun in this game but one. */
      heatMaterial.uniforms.heatMode.value = def.heat.mid === undefined ? 0 : 1;
      heatMaterial.uniforms.heatMid.value = def.heat.mid ?? 0;
    }

    /* --- A SCREEN WHERE THE FILE HAS ONLY A FACE ---------------------
       See `screen` in GUNS. Built in the model's own units and hung off
       the model's own root, so the fit already on that root carries it
       exactly as it carries the metal round it, and it is planar in z
       like the lance's panel so the box measured next is the picture's
       two axes on the same terms. Two triangles, wound to face -z, which
       is the eye once the model has been turned. */
    if (scope && def.screen) {
      const [x0, y0, x1, y1, z] = def.screen.at;
      const g = new THREE.BufferGeometry();
      g.setAttribute('position', new THREE.Float32BufferAttribute([x0, y0, z, x0, y1, z, x1, y1, z, x1, y0, z], 3));
      g.setIndex([0, 1, 2, 0, 2, 3]);
      g.computeBoundingSphere();
      const panel = new THREE.Mesh(g, scope.screenMaterial());
      panel.name = name.toLowerCase() + '-screen';
      root.add(panel);
    }

    /* --- AND WHERE THE SCREEN IS ON ITS OWN MESH --------------------
       Measured off the geometry the file shipped and not off a number
       written here, because the panel's picture is laid out across its
       own bounding box (see js/scope.js): a re-export that moves the
       panel a centimetre moves the picture with it and nothing has to
       be edited. The mesh is planar in z — all thirteen of its vertices
       sit at the same depth — so x and y across that box ARE the two
       axes of the screen. */
    if (scope && (def.display || def.screen)) {
      root.traverse(o => {
        if (!o.isMesh || o.material !== scope.screen) return;
        const a = o.geometry?.attributes?.position;
        if (!a || !a.array) return;
        let lo = [Infinity, Infinity], hi = [-Infinity, -Infinity];
        for (let i = 0; i < a.array.length; i += a.itemSize)
          for (let k = 0; k < 2; k++) { lo[k] = Math.min(lo[k], a.array[i + k]); hi[k] = Math.max(hi[k], a.array[i + k]); }
        if (Number.isFinite(lo[0])) scope.setPanelBox(lo, [hi[0] - lo[0], hi[1] - lo[1]]);
      });
    }

    /* AND THE PART THAT TURNS, named in the file's extras by
       tools/prep-model.mjs — the minigun's barrel set. Spun about its
       own z, which is the axis the barrels run along. */
    const spin = extras.spin ? root.getObjectByName(extras.spin) : null;

    /* AND THE ROUNDS IN IT, for a gun whose file has them as parts — the
       launcher's four rockets, rocket_0 to rocket_3, in firing order. See
       `loaded` in GUNS and update(). */
    const rounds = [];
    if (def.loaded) for (let i = 0; ; i++) {
      const r = root.getObjectByName(def.loaded.prefix + i);
      if (!r) break;
      rounds.push(r);
    }

    const g = {
      def, group, inner, anchors: { nozzle: place(nozzle), pilot: pilot ? place(pilot) : null,
                                    tubes: def.tubes ? def.tubes.map(place) : null },
      gunMaterials, heatMaterial, spin, spinAngle: 0, rounds,
      pilot: null, muzzle: null, muzzleMaterials: [],
    };

    /* the pilot light: a small flame sprite, always on, for a gun that
       has one — the extinguisher does not burn anything and so has not */
    if (g.anchors.pilot) {
      g.pilot = new THREE.Mesh(new THREE.PlaneGeometry(0.036, 0.05), flameMaterial(atlas));
      g.pilot.geometry.translate(0, 0.02, 0);
      g.pilot.renderOrder = 2;
      group.add(g.pilot);
    }

    /* the muzzle effect: two crossed tongues along the barrel, while
       firing. The same frames for both guns, tinted — fire, or the
       white-blue of something very cold leaving a nozzle very fast. */
    g.muzzle = new THREE.Group();
    const add = !!def.muzzle.additive;
    const mA = flameMaterial(atlas, add), mB = flameMaterial(atlas, add);
    const { len, wid } = def.muzzle;
    g.muzzle.add(new THREE.Mesh(tongue(len, wid, false), mA));
    g.muzzle.add(new THREE.Mesh(tongue(len, wid, true), mB));
    g.muzzle.position.copy(g.anchors.nozzle);
    g.muzzle.visible = false;
    g.muzzleMaterials = [mA, mB];
    for (const m of g.muzzleMaterials) {
      m.uniforms.tint.value.fromArray(def.tint || [1, 1, 1]);
      m.uniforms.desat.value = def.cold ? 1 : 0;
    }
    inner.add(g.muzzle);

    /* THE ARC MAW'S CHARGE, for a gun that has one: a ball of blue
       energy hung in its maw and growing with the charge, a halo round
       it, and motes of energy streaming in from all round the prongs —
       see orbTic */
    if (def.orb) {
      g.orb = makeOrb(def.orb);
      g.orb.group.position.copy(g.anchors.nozzle);
      inner.add(g.orb.group);
    }

    return g;
  }

  /**
   * Once a frame. `player` for the bob and the turn; `firing` for the
   * muzzle; `tics` for animation; `dt` so the sway lag is the same at
   * any framerate.
   */
  update(player, firing, tics, dt) {
    if (player && player.weapon) this.setWeapon(player.weapon);
    const G = this.gun;
    if (!G) return;
    const g = G.group;
    const bobX = Math.cos(player.bobPhase) * player.bob * 0.0032;
    const bobY = Math.abs(Math.sin(player.bobPhase)) * player.bob * 0.0026;

    /* The gun lags a turn: swing left and it drifts right for a moment,
       then catches up. The rate is read off the player each tic. */
    const k = 1 - Math.pow(0.001, dt);
    const targetX = -(player.lookRate || 0) * 2.4, targetY = (player.pitchRate || 0) * 1.4;
    this.sway.x += (Math.max(-0.12, Math.min(0.12, targetX)) - this.sway.x) * k;
    this.sway.y += (Math.max(-0.08, Math.min(0.08, targetY)) - this.sway.y) * k;

    /* firing shakes it, a little, and pushes it back */
    this.kick += ((firing ? 1 : 0) - this.kick) * (firing ? 0.35 : 0.12);
    const jx = firing ? (Math.random() - 0.5) * 0.006 : 0;
    const jy = firing ? (Math.random() - 0.5) * 0.005 : 0;

    /* THE GUN IS RAISED, OR IT IS NOT, OR IT IS SOMEWHERE BETWEEN.
       js/scope.js says where it should be (see AIM_AT) and this chases
       it, so putting your eye to the scope is a movement of the weapon
       over about a third of a second rather than a cut. A gun with no
       second hold — every gun but the lance — never leaves zero and
       none of the blending below does anything. */
    const sc = this.scopes[this.active];
    const wantAim = (G.def.aim && sc) ? sc.aim : 0;
    this.aim += (wantAim - this.aim) * (1 - Math.pow(0.0015, dt));
    const a = G.def.aim ? this.aim : 0;
    const mix = (hip, aimed) => hip + (aimed - hip) * a;

    /* `out` is a push straight back along the view — z alone, kick and
       all — see the note on the bore in GUNS for why not the whole
       vector */
    /* and `pos` is a gun's own offset on the shared hold — a heavy gun
       carried in both hands sits nearer the middle than a hose does */
    const off = G.def.pos || [0, 0, 0];
    const aoff = G.def.aim?.pos || off;
    const out = mix(G.def.out ?? 1, G.def.aim?.out ?? G.def.out ?? 1);
    /* AND THE BOB AND THE SWAY GO AWAY WITH IT. A weapon at your
       shoulder does not swing about: what the hip hold reads as life,
       the aimed one reads as a shake you cannot sight through. */
    const steady = 1 - a * 0.88;
    g.position.set(VIEW.pos[0] + mix(off[0], aoff[0]) + (bobX + jx) * steady,
                   VIEW.pos[1] + mix(off[1], aoff[1]) - bobY * steady + jy * steady,
                   (VIEW.pos[2] + mix(off[2], aoff[2]) + this.kick * 0.025) * out);
    /* and `rot` is a gun's own turn on the shared one — pitch, yaw,
       roll — for a gun held square rather than angled in from a corner */
    const rot = G.def.rot || [0, 0, 0];
    const arot = G.def.aim?.rot || rot;
    g.rotation.set(VIEW.pitch + mix(rot[0], arot[0]) + this.sway.y * steady,
                   VIEW.yaw + mix(rot[1], arot[1]) + this.sway.x * steady,
                   VIEW.roll + mix(rot[2], arot[2]) + this.sway.x * 0.4 * steady, 'YXZ');
    g.updateMatrixWorld(true);

    /* the pilot, flickering, on its anchor */
    const flick = 0.85 + 0.15 * Math.sin(tics * 1.7) * Math.cos(tics * 0.53);
    let pv = null;
    if (G.pilot) {
      pv = this._tmp.copy(G.anchors.pilot);
      G.inner.localToWorld(pv);
      /* AND THEN BACK OUT OF THE WORLD AGAIN, because the flame is a
         child of the GROUP and not of the model — it has to be, or it
         would inherit the half-turn that points the barrel at the
         camera and we would be looking at the back of the quad.

         This line was missing and the pilot light sat a third of the
         gun's length below and in front of the barrel, measured at
         0.537m off on a gun 1.4m long. A world-space point assigned to
         `position` is read in the PARENT's space, so the group's own
         transform — the whole of VIEW.pos, the yaw, the bob — was
         applied to it a second time. The tell was that the glow it
         throws ON the gun was in the right place while the flame was
         not: the shader takes `pv` in view space and is correct, and
         only the mesh needed converting. The muzzle never had the bug
         because it is parented to the model and given the anchor in
         the model's own units. */
      G.pilot.position.copy(pv);
      G.group.worldToLocal(G.pilot.position);
      G.pilot.scale.set(flick, 0.8 + flick * 0.35, 1);
      G.pilot.material.uniforms.frame.value = (tics >> 1) % this.frames;
      G.pilot.visible = !firing;
    }

    /* THE BARRELS TURN AND THE BARRELS HEAT, both read off the player,
       who owns the numbers (see Player.spin and Player.heat): the spin
       is 0..1 of full speed, so the set winds up before the first round
       and runs down after the last, and the heat is 0..1 of a barrel
       that should have stopped. Neither is a frame count — both are
       states, so a pause holds them where they are. */
    if (G.spin) {
      const rate = (player.spin || 0) * (G.def.spin || 0) * Math.PI * 2;
      G.spinAngle = (G.spinAngle + rate * dt) % (Math.PI * 2);
      G.spin.rotation.z = G.spinAngle;
    }
    /* A TUBE IS EMPTY ONCE ITS ROCKET HAS GONE. The tubes fire in order
       from the first while the ammo counts down (see Missiles.launch),
       so with n left the loaded ones are the last n. */
    if (G.rounds.length) {
      const left = Math.max(0, Math.min(G.rounds.length, player.ammo?.[G.def.loaded.ammo] | 0));
      G.rounds.forEach((r, i) => { r.visible = i >= G.rounds.length - left; });
    }
    /* AND OFF THE NUMBER THE DEF NAMES, not off one called `heat`:
       two guns cook now and they cook separately, so a minigun put
       away glowing does not hand its barrels to the lance. */
    if (G.heatMaterial) G.heatMaterial.uniforms.heat.value = player[G.def.heat?.from || 'heat'] || 0;

    /* the muzzle, only while firing — and on a gun with more than one
       mouth, at the one that has just gone: the player says which (see
       Player.launchTube), so a salvo is four flashes that walk across
       the front of the box rather than one in the middle of it */
    if (G.anchors.tubes && player.launchTube >= 0) G.muzzle.position.copy(G.anchors.tubes[player.launchTube % G.anchors.tubes.length]);
    G.muzzle.visible = !!firing;
    if (firing) {
      const s = 0.85 + Math.random() * 0.3;
      G.muzzle.scale.set(s, s, 0.9 + Math.random() * 0.35);
      G.muzzleMaterials[0].uniforms.frame.value = tics % this.frames;
      G.muzzleMaterials[1].uniforms.frame.value = (tics + 7) % this.frames;
    }

    if (G.orb) orbTic(G.orb, player, firing, dt, tics);

    /* and what they throw on the gun. A gun with no pilot gets no pilot
       glow — an extinguisher lit by a flame it does not have would be
       the one thing on screen saying it is a flamethrower. */
    const nv = this._tmp2.copy(G.anchors.nozzle);
    G.inner.localToWorld(nv);
    for (const m of G.gunMaterials) {
      m.uniforms.glow.value += ((firing ? 1 : 0) - m.uniforms.glow.value) * 0.4;
      m.uniforms.glowPos.value.copy(nv);
      m.uniforms.pilot.value = pv ? 0.55 * flick : 0;
      if (pv) m.uniforms.pilotPos.value.copy(pv);
    }
  }

  /** The nozzle, in the WORLD's coordinates (game x, y, z), for a stream
   *  to be born at. Projected as a ray through this scene's camera and
   *  back out of the world's, so it leaves the end of the gun as drawn
   *  whatever the two fields of view are. */
  nozzleWorld(worldCamera, out = { x: 0, y: 0, z: 0 }) {
    const G = this.gun;
    if (!G) return null;
    return this._toWorld(G, G.anchors.nozzle, worldCamera, out);
  }

  /** One of the launcher's four mouths, on the same terms as the nozzle
   *  — or null for a gun with only the one. */
  tubeWorld(i, worldCamera, out = { x: 0, y: 0, z: 0 }) {
    const G = this.gun;
    if (!G || !G.anchors.tubes) return null;
    return this._toWorld(G, G.anchors.tubes[i % G.anchors.tubes.length], worldCamera, out);
  }

  _toWorld(G, anchor, worldCamera, out) {
    const nv = this._tmp2.copy(anchor);
    G.inner.localToWorld(nv);
    const dist = Math.min(nv.length() * UNITS_PER_METRE, NOZZLE_REACH);
    const ndc = this._ndc.copy(nv).project(this.camera);
    ndc.z = 0.5;
    const wp = ndc.unproject(worldCamera);
    const dir = wp.sub(worldCamera.position).normalize();
    const w = dir.multiplyScalar(dist).add(worldCamera.position);
    out.x = w.x; out.y = -w.z; out.z = w.y;
    return out;
  }
}

/* ---------------------------------------------------------------------
   THE ARC MAW'S CHARGE

   A white-hot core, a blue halo round it that breathes, and motes of
   blue energy born on a shell round the prongs that fall into the
   middle faster as they near it — more of them, and from further out,
   the higher the charge. All additive sprites in the gun's own scene,
   so the ball is always in the maw however the gun moves, and never
   behind a wall the gun is poking through. The discharge is a flash of
   the halo, big and gone in a fifth of a second.
   --------------------------------------------------------------------- */
let glowTex = null;
function glowTexture() {
  if (glowTex || typeof document === 'undefined') return glowTex;
  const c = document.createElement('canvas'); c.width = c.height = 64;
  const x = c.getContext('2d');
  const gr = x.createRadialGradient(32, 32, 0, 32, 32, 32);
  gr.addColorStop(0, 'rgba(255,255,255,1)');
  gr.addColorStop(0.25, 'rgba(200,230,255,0.9)');
  gr.addColorStop(0.6, 'rgba(70,140,255,0.35)');
  gr.addColorStop(1, 'rgba(20,60,255,0)');
  x.fillStyle = gr; x.fillRect(0, 0, 64, 64);
  glowTex = new THREE.CanvasTexture(c);
  glowTex.colorSpace = THREE.SRGBColorSpace;
  return glowTex;
}

function orbSprite(color, opacity = 1) {
  const m = new THREE.SpriteMaterial({ map: glowTexture(), color, transparent: true, opacity,
                                       blending: THREE.AdditiveBlending, depthWrite: false, depthTest: false,
                                       toneMapped: false, fog: false });
  const s = new THREE.Sprite(m);
  s.renderOrder = 6;
  return s;
}

function makeOrb(def) {
  const group = new THREE.Group();
  const halo = orbSprite(0x3f7dff, 0.8), core = orbSprite(0xdff0ff, 1), flash = orbSprite(0x8fc0ff, 1);
  group.add(halo, core, flash);
  const motes = [];
  for (let i = 0; i < def.motes; i++) {
    const s = orbSprite(i % 3 ? 0x5a9cff : 0xcfe6ff, 1);
    s.visible = false;
    group.add(s);
    motes.push({ s, x: 0, y: 0, z: 0, age: 0, life: 0, live: false });
  }
  return { def, group, halo, core, flash, motes, flashT: 0, was: 0, spawn: 0 };
}

function orbTic(o, player, firing, dt, tics) {
  const c = player.arcCharging ? (player.arcCharge || 0) : 0;
  const R = o.def.radius, reach = o.def.reach;
  /* the discharge: the charge went to nothing with the trigger up */
  if (o.was > 0.02 && c === 0 && firing) o.flashT = 1;
  o.was = c;
  const breathe = 1 + 0.12 * Math.sin(tics * 0.9) + 0.06 * Math.sin(tics * 2.3);
  const r = c > 0 ? R * (0.12 + 0.88 * Math.sqrt(c)) * breathe : 0;
  o.core.visible = o.halo.visible = r > 0;
  o.core.scale.setScalar(r * 1.2);
  o.halo.scale.setScalar(r * (3.4 + 0.6 * Math.sin(tics * 0.4)));
  o.halo.material.opacity = 0.45 + 0.45 * c;
  o.flashT = Math.max(0, o.flashT - dt * 5);
  o.flash.visible = o.flashT > 0;
  o.flash.scale.setScalar(R * (2 + 9 * (1 - o.flashT)));
  o.flash.material.opacity = o.flashT;
  /* the motes: born on a shell round the maw, drawn in, faster near it */
  o.spawn += c > 0 ? dt * (18 + 90 * c) : 0;
  for (const m of o.motes) {
    if (!m.live) {
      if (o.spawn < 1) { m.s.visible = false; continue; }
      o.spawn -= 1;
      const u = Math.random() * 2 - 1, a = Math.random() * Math.PI * 2, rr = reach * (0.55 + 0.45 * Math.random()) * (0.7 + 0.5 * c);
      const q = Math.sqrt(1 - u * u);
      m.x = Math.cos(a) * q * rr; m.y = Math.sin(a) * q * rr; m.z = u * rr * 0.6 - rr * 0.25;
      m.age = 0; m.life = 0.35 + Math.random() * 0.3; m.live = true;
    }
    m.age += dt;
    const k = Math.min(1, dt * (3 + 9 * m.age / m.life));
    m.x -= m.x * k; m.y -= m.y * k; m.z -= m.z * k;
    const d = Math.hypot(m.x, m.y, m.z);
    if (m.age >= m.life || d < r * 0.5 || c === 0) { m.live = false; m.s.visible = false; continue; }
    m.s.visible = true;
    m.s.position.set(m.x, m.y, m.z);
    m.s.scale.setScalar(R * (0.22 + 0.25 * Math.min(1, d / reach)));
    m.s.material.opacity = Math.min(1, m.age / 0.08);
  }
}
