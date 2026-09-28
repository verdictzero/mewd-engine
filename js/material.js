/* =====================================================================
   MEWD — materials, and light that steps instead of fading
   =====================================================================

   There is one material in this game and it is unlit. Nothing here has a
   normal, nothing has a specular, nothing is lit by a light source. A
   surface's brightness is a number the map author wrote down, darkened by
   how far away it is, and quantised into 32 steps on the way.

   That last part is the whole trick. Doom did not multiply anything by
   anything — it kept 32 pre-darkened copies of the palette and picked
   one. So light does not fade down a corridor, it STEPS down, and you can
   see the steps, and after thirty years those steps are what the eye
   reads as "this is that kind of game". Smooth falloff costs nothing and
   throws it all away.

   FAKE CONTRAST comes free with the same idea. Doom nudged the light
   level up on walls running east-west and down on walls running
   north-south. It is not a lighting model — there is no sun and the
   nudge is the same at midnight — but it means a corner between two walls
   is always visible, in a renderer with no shading at all. Baked into the
   vertex light by the geometry builder, so it costs nothing here either.

   SMOKE is the one thing that moves. As the store burns, smokeDensity
   climbs and the far end of every aisle goes grey, which is both the
   atmosphere and an honest gameplay signal: when you can no longer see
   the checkouts from Aisle 6, it is time to leave.

   THE AIR is the other thing, and it is always there: every surface
   fades with distance toward the sky behind it — literally a texel of
   the sky bake, in the fragment's azimuth — so the far edge of the
   world is the sky and not a cut. How far the air lets you see is the
   weather's, and it is also the draw distance. See SIGHT.txt.

   THE SHADING IS EXPORTED AS GLSL, not only as materials. The forest,
   the particles and the flame all draw with their own vertex paths —
   instanced, animated, burning — but every one of them has to sit in
   the same light as the walls or it reads as a sticker on the picture.
   So the lighting is two GLSL strings any shader can splice in, and the
   three materials below are only the plain ways of using them.
   ===================================================================== */

import * as THREE from 'three';
import { EMBER_RAMP } from './palette.js';
import { SKY_H } from './skyart.js';

/* Every material in the game shares these objects. Mutate .value on one
   and the whole store changes on the next frame — no walking a scene
   graph, no keeping a list. */
export const world = {
  globalLight:  { value: 1.0 },      // damage flash, light-amp pickup, blackout
  lightFalloff: { value: 1400.0 },   // units at which the diminishing bottoms out
  minLight:     { value: 0.12 },     // how dark the far end of a lit room gets
  /* THE AIR. Always on. A surface starts to go at airNear and has gone
     entirely at airFar, and what it goes TO is not a colour anybody
     tuned: it is a texel of the sky — skyTex's horizon row, in the
     fragment's own azimuth — so a wall at the end of the street fades
     into precisely what is behind it. airFar is therefore also the
     draw distance, and the weather sets both (js/weather.js). With no
     sky texture bound, as headless, the air fades to black, which is
     the night this game had before it had a sky. */
  airNear:      { value: 1200.0 },
  airFar:       { value: 14000.0 },
  skyTex:       { value: null },
  /* where the eye is, in the renderer's axes, for the azimuth */
  eyePos:       { value: new THREE.Vector3(0, 0, 0) },
  /* HOW MUCH LIGHT THE SKY IS GIVING. An outdoor vertex's own light is
     the floor and this lifts it — see worldBand — so a dawn is one
     uniform and no rebuild. 0.08 is two in the morning. */
  skyLight:     { value: 0.08 },
  /* THE SMOKE, which used to be called the fog and used to be the only
     one there was. Warm, lit by the fire under it, and driven by how
     much of the store is alight. It goes on AFTER the air, because it
     is between you and everything, the sky included. */
  smokeColor:   { value: new THREE.Color(0.46, 0.34, 0.24) },
  smokeNear:    { value: 300.0 },
  smokeFar:     { value: 2200.0 },
  smokeDensity: { value: 0.0 },
  tint:         { value: new THREE.Color(1, 1, 1) },  // pain red, pickup gold

  /* THE FIRE GLOW. One light, for the whole game.

     Everything else here is unlit on purpose, but a store that is
     burning down and does not get brighter as it burns is a store that
     is not really burning. So there is exactly one point light, parked
     at the centre of mass of whatever is alight nearest the player, and
     its intensity is how much of it there is. One light is enough
     because from inside a burning aisle the whole aisle is the light —
     you never see two fires as two sources, you see the room glowing.

     It is added AFTER the light is quantised into its 32 steps, so the
     glow slides smoothly over the banding instead of fighting it. */
  fireLightPos:   { value: new THREE.Vector3(0, -10000, 0) },
  fireLightRange: { value: 512.0 },
  fireLight:      { value: 0.0 },
  fireLightColor: { value: new THREE.Color(1.0, 0.55, 0.18) },

  /* ------------------------------------------------------------------
     AND A SECOND LIGHT, WHICH IS A LINE

     The paragraph below this one says a spotlight was taken out and
     that one light is enough. It is enough for FIRE, and the reasoning
     holds: a burning aisle is one glow because you never see two fires
     as two sources. It does not hold for the positron lance, which is
     not a source at a point — it is a column eight metres across drawn
     from the muzzle to the far side of the map, and the whole thing is
     lit. A point light at the muzzle would put a bright spot on the
     wall you are standing next to and leave the street the beam is
     actually crossing in the dark, which is exactly backwards.

     So this one is a SEGMENT: a start, a direction, a length, and a
     radius round the axis. Every fragment measures its distance to the
     nearest point ON THE LINE, which is one dot product and one
     subtract, and is lit by that. A person standing beside the column a
     hundred metres away is lit as hard as the wall behind the muzzle,
     because they are as near the light.

     AND IT IS DIFFERENTIAL AND RANDOMISED, at the user's request, which
     is the part that makes it read as a discharge rather than as a
     lamp. `beamSeed` is a clock; the noise is keyed off the fragment's
     own world position rounded to a coarse grid, so two objects either
     side of the column flicker at different rates and different phases
     and neither of them flickers with the frame. What you get is a
     street where every surface is being lit by the same thing and none
     of them agrees about it, which is what a fifty-megajoule line of
     plasma a few metres away would actually look like.

     It OUTLIVES THE BEAM. js/beam.js leaves the axis where it was and
     fades the intensity over a second and a half, so the street stays
     lit by a thing that has already gone — the after-image of the shot
     — which is the "post charge" half of the same request.
     ------------------------------------------------------------------ */
  beamPos:        { value: new THREE.Vector3(0, -10000, 0) },
  beamDir:        { value: new THREE.Vector3(0, 0, 1) },
  beamLen:        { value: 0.0 },
  beamRange:      { value: 700.0 },
  beam:           { value: 0.0 },
  beamSeed:       { value: 0.0 },
  beamColor:      { value: new THREE.Color(0.62, 1.0, 0.78) },

  /* THERE WAS A SECOND LIGHT HERE FOR AN AFTERNOON, and it is worth a
     paragraph because the reasoning is the file's: the gunship's
     searchlight (js/vtol.js) was a lit cone — spotPos, spotDir, two
     cone cosines, a range and a colour — added on top of the banded
     light the way the fire glow is, on every surface that shades with
     worldShade. It worked. It is gone at the user's request, and what
     is kept instead is the LENS FLARE at the lamp, which is the part
     you actually read a searchlight by at night.

     What it cost while it was here was a branch and a normalize in
     every fragment of every wall, floor, car, tree, sprite and puff in
     the game, for a pool of light on the tarmac that a beam with no
     shadow map put through the roof of the shop as readily as onto the
     lot. One light in this file is the right number, and it is the
     fire.

     THE COALS. One clock for everything in the game that is still
     glowing after the flame has gone — the burning trees run on it, and
     so does every charred and gutted surface in the store. Seconds. */
  emberTime: { value: 0.0 },

  /* HOW BURNT EVERY PIECE OF FLOOR IS, as a picture.

     The store's surfaces used to know three things about the fire:
     untouched, charred, gutted. Two steps, both of them a texture swap,
     and between them nothing — an aisle could lose half its stock
     without a pixel of it changing, and then change all at once.

     THE FIRST FIX WAS ONE TEXEL PER SECTOR and it was the wrong picture,
     which the user reported as z-fighting. A sector's progress is one
     number, so every surface in it sooted together, and the sectors of
     this map are big axis-aligned rectangles: a burnt aisle met a clean
     cross-aisle along a dead-straight line, exactly vertical or exactly
     horizontal on screen, with a different texture and a different light
     on each side. That does not read as a fire. It reads as a fault.

     So the picture is the FIRE'S OWN GRID: 32-unit cells, the same ones
     it spreads through, one byte each, sampled here by WORLD POSITION
     with a linear filter. The soot front then creeps at the resolution
     the fire has and crosses a sector boundary without knowing it is
     there. It also answers the question better for the surfaces that are
     not floors — a wall reads the cells it stands in and a ceiling the
     cells under it, rather than whichever sector it was filed under.

     `burnOrigin` and `burnCell` are the grid's corner and pitch in world
     units, and `burnCols` by `burnRows` is its size in cells — which is
     also, exactly, the size of the texture, so the fetch divides by it
     and a position off the edge of the fire's world reads zero rather
     than the clamped edge. See Game.ticBurnGrid. */
  burnGrid:   { value: null },
  burnOrigin: { value: new THREE.Vector2(0, 0) },
  burnCell:   { value: 32.0 },
  burnCols:   { value: 1.0 },
  burnRows:   { value: 1.0 },
  emberRamp: { value: EMBER_RAMP.map(c => new THREE.Vector3(c[0], c[1], c[2])) },

  /* THE THERMAL SIGHT'S SWITCH. Nought for every frame anybody looks
     at, and one for exactly one render call a frame: the feed
     js/thermal.js draws for the screen on the side of the quad
     launcher, during which every surface that shades through this file
     answers HOW WARM IT IS instead of what colour it is — the one
     number, in all three channels — and the screen turns that number
     into a palette. See thermalOf, and the THERMAL block at the bottom
     of COMMON_FRAG.

     A UNIFORM AND NOT A SECOND SET OF MATERIALS, for the reason every
     uniform in this object is shared: it is the same scene, the same
     culling and the same draw calls as the frame, so the scope can
     only ever show what is there, and nothing has to be kept in step. */
  thermal: { value: 0.0 },

  /* ------------------------------------------------------------------
     A MAP'S OWN LIGHT AND FOG, set by MEWD Editor's World panel (see
     applyMapLight in js/editor/doc.js). All of them do nothing at
     their defaults, so the game's own levels are untouched.

       lightColor   the colour of all the light in the map, multiplied
                    into every lit surface (a global light colour)
       ambientColor light that is everywhere, colour times strength,
                    ADDED to every surface however dark its sector — the
                    floor a pitch-black room never goes below
       fogAmbient   how much of that ambient light is in the fog too, so
                    a green ambient makes every fog a little green
       fogDefault   the fog of anything without a sector's own: rgb and
                    a density (0 is none; see sectorFog below)
       airColor, airOverride
                    the far haze's colour, in place of the sky's horizon
                    when airOverride is 1
     ------------------------------------------------------------------ */
  lightColor:   { value: new THREE.Color(1, 1, 1) },
  ambientColor: { value: new THREE.Color(0, 0, 0) },
  fogAmbient:   { value: 1.0 },
  fogDefault:   { value: new THREE.Vector4(0, 0, 0, 0) },
  airColor:     { value: new THREE.Color(0, 0, 0) },
  airOverride:  { value: 0.0 },

  /* THE SECTOR GRID: what light, colour and fog each spot of the map
     has, as two small pictures over its floor plan (buildSectorGrid in
     js/sectorgrid.js). What is not level geometry — a sprite, a tree, a
     3D model — reads it at its own foot and is lit and fogged by the
     sector it stands in, Doom's rule for a thing. Off (sectorOn 0) for
     the game's own levels, which light their things themselves.
       sectorA  rgb: the thing colour (Doom 64's, times the sector's light
                colour); a: the sector's light
       sectorB  rgb: the sector's fog colour; a: its density / 100, or 0
                for the map's default fog
       sectorC  rg: how high its fog reaches (see FOG_GLSL)
       sectorRect  the grid's map-space origin, and one over its size */
  sectorA:      { value: null },
  sectorB:      { value: null },
  sectorC:      { value: null },
  sectorRect:   { value: new THREE.Vector4(0, 0, 1, 1) },
  sectorOn:     { value: 0.0 },
  /* 1 when a map from the editor has any fog: the fog is then followed
     along each line of sight (FOG_GLSL) rather than read off the surface */
  fogMarch:     { value: 0.0 },
};

/* The sector grid, for a vertex shader: its uniforms and the lookup —
   see world.sectorA. `foot` is in renderer axes. */
export const SECTOR_GRID_GLSL = /* glsl */`
uniform sampler2D sectorA;
uniform sampler2D sectorB;
uniform vec4  sectorRect;
uniform float sectorOn;
vec2 sectorUv(vec3 foot) { return (vec2(foot.x, -foot.z) - sectorRect.xy) * sectorRect.zw; }
/* the light (a) and thing colour (rgb) of the sector at a foot */
vec4 sectorLightAt(vec3 foot) { return texture2D(sectorA, sectorUv(foot)); }
/* its fog as worldShade wants it: rgb and density, or -1 for the map's */
vec4 sectorFogAt(vec3 foot) {
  vec4 b = texture2D(sectorB, sectorUv(foot));
  return b.a > 0.0 ? vec4(b.rgb, b.a * 100.0) : vec4(0.0, 0.0, 0.0, -1.0);
}
`;

/**
 * PUT A MAP'S OWN LIGHT AND FOG ON THE WORLD (see world.lightColor),
 * from level.mapLight (mapLightOf in js/editor/doc.js) — or back to
 * doing nothing, for a level without one.
 */
export function applyMapLight(m) {
  const w = world;
  /* written field by field: the same objects every material holds */
  const rgb = (c, [r, g, b]) => { c.r = r; c.g = g; c.b = b; };
  const v4 = (v, [x, y, z, ww]) => { v.x = x; v.y = y; v.z = z; v.w = ww; };
  m = m || { lightColor: [1, 1, 1], ambient: [0, 0, 0], fogAmbient: 1, fog: [0, 0, 0, 0], override: false };
  rgb(w.lightColor.value, m.lightColor);
  rgb(w.ambientColor.value, m.ambient);
  w.fogAmbient.value = m.fogAmbient;
  v4(w.fogDefault.value, m.fog);
  /* an override puts the fog's colour on the far haze too */
  rgb(w.airColor.value, m.fog);
  w.airOverride.value = m.override ? 1 : 0;
}

/* THE COLOUR OF A STREET LAMP'S LIGHT, in one place. Mercury vapour: a
   cold white with green in it, which is what every American street was
   lit by from the fifties until the sodium came. Two things are drawn
   in it and they have to agree, or the pool on the ground is a
   different lamp from the one over it: the pavement under a lamp is
   tinted by it here (vLamp, below), and js/lamplight.js draws the flare
   at the luminaire in it. */
export const LAMP_LIGHT = [0.70, 1.0, 0.86];

/* The uniform declarations every lit fragment shader needs, matching
   `worldUniforms()` below one for one. */
export const WORLD_UNIFORMS_GLSL = /* glsl */`
uniform float globalLight;
uniform float lightFalloff;
uniform float minLight;
uniform float airNear;
uniform float airFar;
uniform sampler2D skyTex;
uniform vec3  eyePos;
uniform float skyLight;
uniform vec3  smokeColor;
uniform float smokeNear;
uniform float smokeFar;
uniform float smokeDensity;
uniform vec3  tint;
uniform vec3  fireLightPos;
uniform float fireLightRange;
uniform float fireLight;
uniform vec3  fireLightColor;
uniform vec3  beamPos;
uniform vec3  beamDir;
uniform float beamLen;
uniform float beamRange;
uniform float beam;
uniform float beamSeed;
uniform vec3  beamColor;
uniform float emberTime;
uniform vec3  emberRamp[8];
uniform sampler2D burnGrid;
uniform vec2  burnOrigin;
uniform float burnCell;
uniform float burnCols;
uniform float burnRows;
uniform float thermal;
uniform vec3  lightColor;
uniform vec3  ambientColor;
uniform float fogAmbient;
uniform vec4  fogDefault;
uniform vec3  airColor;
uniform float airOverride;
uniform sampler2D sectorB;
uniform sampler2D sectorC;
uniform vec4  sectorRect;
uniform float sectorOn;
uniform float fogMarch;
`;

/* The two halves of the lighting, as functions.

   worldBand: a surface's own light, diminished by distance and snapped
   to Doom's 32 steps. `sky` is how much of the light arrives from the
   sky rather than a fitting (stretches the falloff, lifts its floor);
   `fullbright` short-circuits the lot for things that are their own
   light.

   worldShade: the banded light applied to a colour, then the fire glow
   on top of the banding, then the smoke. */
/* ---------------------------------------------------------------------
   THE FOG ALONG A LINE OF SIGHT

   At the user's request, fog FADES from sector to sector, and from a
   sector into the sky, instead of stopping at a line. A surface used to
   be fogged by its own sector's fog over the whole distance to it: a
   floor half in a fogged room had a hard edge down the middle where the
   sector changed, standing in thick fog you saw a clear sky, and the
   fog never came in around you as you walked into it.

   So the fog is FOLLOWED from the eye to what is seen, over the sector
   grid (js/sectorgrid.js): the line is cut into FOG_STEPS pieces,
   finer near the eye, and where a piece crosses from one sector's air
   into another's the crossing is found by halving it, FOG_HALVINGS
   times. Each stretch fogs by its own air — its colour, and its density
   the GZDoom way, half-way in at 25600/density units — so fog thickens
   continuously with how much of it you look through. Walk into a fogged
   room and it closes round you step by step; look out of it and what is
   beyond is hazed by the few metres you are still standing in. The sky
   is followed the same way, out to airFar, so it fades into the fog
   you are in and comes back as you leave it.

   The end of the line is the surface's own fog (vFog) where it has one,
   so the air right at a wall is exactly its sector's.

   AND IT HAS A TOP. A fog fills its sector up to the ceiling, or under
   the sky up to FOG_TOP over the floor (js/sectorgrid.js), and above
   that thins away, e-folding every FOG_FADE units — so a fogged field
   seen from outside is a bank of fog fading up into the sky, not a
   column to the stars, and standing in it the sky overhead is dimmed
   by the fog above you and no more. A stretch of the line is fogged by
   the mean of that profile over the heights it climbs through, which
   has a closed form (fogG).
   ------------------------------------------------------------------- */
export const FOG_GLSL = /* glsl */`
#define FOG_STEPS 16
#define FOG_HALVINGS 5
#define FOG_FADE 128.0
/* the air at a point (renderer axes): its sector's fog, or the map's */
vec4 fogAirAt(vec3 p) {
  if (sectorOn < 0.5) return fogDefault;
  vec2 uv = (vec2(p.x, -p.z) - sectorRect.xy) * sectorRect.zw;
  if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) return fogDefault;
  vec4 b = texture2D(sectorB, uv);
  return b.a > 0.0 ? vec4(b.rgb, b.a * 100.0) : fogDefault;
}
/* how high the fog at a point reaches, and how it ends there: x the
   top, y how far over it the fog thins away — FOG_FADE under the sky,
   and next to nothing under a roof, where the fog stops at the ceiling
   and there is none in the air over the building */
vec2 fogTopAt(vec3 p) {
  if (sectorOn < 0.5) return vec2(1e9, FOG_FADE);
  vec2 uv = (vec2(p.x, -p.z) - sectorRect.xy) * sectorRect.zw;
  if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) return vec2(1e9, FOG_FADE);
  vec3 t = floor(texture2D(sectorC, uv).rgb * 255.0 + 0.5);
  return vec2(t.x * 256.0 + t.y - 32768.0, t.z > 127.0 ? 1.0 : FOG_FADE);
}
/* the fog's thickness summed up to height z, under a top: all of it
   below, thinning away above */
float fogG(float z, vec2 top) {
  return z <= top.x ? z : top.x + top.y * (1.0 - exp((top.x - z) / top.y));
}
/* its mean between two heights */
float fogThick(float z0, float z1, vec2 top) {
  float dz = z1 - z0;
  if (abs(dz) < 1.0) { float z = 0.5 * (z0 + z1); return z <= top.x ? 1.0 : exp((top.x - z) / top.y); }
  return (fogG(z1, top) - fogG(z0, top)) / dz;
}
bool fogSame(vec4 a, vec4 b) {
  vec4 d = abs(a - b);
  return max(max(d.r, d.g), d.b) < 0.01 && d.a < 0.2;
}
/* one stretch of air, len long, from height z0 to z1 under a fog top:
   what it lets through (T) and adds */
void fogSpan(inout vec3 add, inout float T, vec4 fg, float len, float z0, float z1, vec2 top) {
  if (fg.a <= 0.0 || len <= 0.0) return;
  float t = exp2(-len * fg.a * fogThick(z0, z1, top) / 25600.0);
  add += T * (1.0 - t) * (fg.rgb * lightColor + ambientColor * fogAmbient);
  T *= t;
}
/* the fog from a to b, endFog being the air at b: rgb what it adds, a
   how much of what is at b gets through */
vec4 fogAlong(vec3 a, vec3 b, vec4 endFog) {
  float len = distance(a, b);
  vec3 add = vec3(0.0);
  float T = 1.0;
  vec4 gPrev = fogAirAt(a);
  vec2 tPrev = fogTopAt(a);
  float sPrev = 0.0;
  for (int i = 1; i <= FOG_STEPS; i++) {
    float u = float(i) / float(FOG_STEPS);
    float s = u * u;                        /* finer near the eye */
    vec3 p = mix(a, b, s);
    vec4 g = i == FOG_STEPS ? endFog : fogAirAt(p);
    vec2 top = fogTopAt(p);
    float z0 = mix(a.y, b.y, sPrev), z1 = p.y;
    if (fogSame(g, gPrev)) {
      /* the same air: its top is the one it had where it began, so a
         line of sight over a street of kerbs and roofs is not banded by
         each one's slightly different height */
      fogSpan(add, T, gPrev, (s - sPrev) * len, z0, z1, tPrev);
      top = tPrev;
    } else {
      float lo = sPrev, hi = s;
      for (int k = 0; k < FOG_HALVINGS; k++) {
        float m = 0.5 * (lo + hi);
        if (fogSame(fogAirAt(mix(a, b, m)), gPrev)) lo = m; else hi = m;
      }
      float cut = 0.5 * (lo + hi), zc = mix(a.y, b.y, cut);
      fogSpan(add, T, gPrev, (cut - sPrev) * len, z0, zc, tPrev);
      fogSpan(add, T, g, (s - cut) * len, zc, z1, top);
    }
    gPrev = g;
    tPrev = top;
    sPrev = s;
    if (T < 0.002) break;
  }
  return vec4(add, T);
}
`;

export const WORLD_SHADE_GLSL = /* glsl */`
${FOG_GLSL}
/* ---------------------------------------------------------------------
   THE COALS ON A BURNT SURFACE

   A charred wall used to be a picture of embers: the ash and the little
   orange specks were baked into the texture and they sat there, dead, at
   the exact moment the game most wants to look alive. The burning trees
   have never had that problem — their shader runs the eight-colour ember
   ramp against a clock — and this is the same maths, on the same ramp,
   on the same clock, so that a charred aisle and a charred fir are one
   fire going out rather than two effects that happen to be orange.

   WHERE THE COALS SIT, with no second texture to say so: a scatter of
   world-space cells about five units across, kept only where the surface
   is ALREADY DARK. Coals live in the recesses of a burnt thing — the
   char between the boards, the gap between the studs — and a burnt
   texture's own dark places are exactly those recesses. So the texture
   picks the spots and the shader lights them.

   It costs nothing where nothing has burnt, which is most of the game
   and all of it until you do something.
   ------------------------------------------------------------------- */
float emberHash(vec3 c) {
  return fract(sin(dot(c, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

/* ---------------------------------------------------------------------
   A PATCH THAT IS NOT A CUBE

   Everything the burn draws is a scatter over floor(wpos * k), which is
   a lattice of axis-aligned cells — and an axis-aligned cell on a floor
   or a ceiling is a SQUARE. One scale of them reads as a chequerboard,
   which is what the soot and the ash were doing: rectangles a bay across
   with dead-straight edges, in step with the rectangles on the ceiling
   above them.

   The fix is not a finer lattice, which only makes smaller squares. It
   is to move the point before looking it up. emberWarp offsets wpos by a
   coarse vector field, so the lattice boundaries wander by most of a
   cell and a patch comes out with a ragged outline at the warp's scale
   rather than a straight one at its own.

   Four hashes and a multiply, and none of it runs anywhere nothing has
   burnt: every caller tests its amount before asking.
   ------------------------------------------------------------------- */
vec3 emberWarp(vec3 wpos, float cells, float amount) {
  vec3 c = floor(wpos * cells);
  return wpos + (vec3(emberHash(c),
                      emberHash(c + 13.0),
                      emberHash(c + 29.0)) - 0.5) * amount;
}

/* A patch field: three scales of scatter over a warped lattice, so it
   has structure at a bay, at a shelf and at a hand. */
float emberPatch(vec3 wpos) {
  vec3 w = emberWarp(wpos, 0.09, 26.0);
  return emberHash(floor(w * 0.028)) * 0.52          // a bay across
       + emberHash(floor(w * 0.075) + 31.0) * 0.29   // the shape in it
       + emberHash(floor(w * 0.21) + 71.0) * 0.19;   // and its torn edge
}

vec3 emberOf(float charAmt, vec3 wpos, float lum, float depth) {
  if (charAmt <= 0.001) return vec3(0.0);
  /* CHUNKY, AND THERE ARE NOT MANY. The first cut used cells five units
     across and lit a quarter of them, which at a grazing angle put more
     coals on a ceiling than there were pixels to draw them in: it read
     as television static rather than as a fire going out. Fourteen-unit
     cells are about the size of a coal you would see across a shop, and
     one in twelve of them is alight. */
  /* TWO SIZES OF COAL, and the smaller one is the detail the first cut
     of this could not have had. Fourteen-unit cells are the size of a
     coal you see across a shop and one in twelve is alight, which is
     right and is also, on its own, one dot repeated. A second scatter at
     four units — rarer, and cut off much harder by distance so it can
     never become the aliasing the big one was tuned away from — is the
     SPARK in among them, and the pair read as a fire going out rather
     than as a texture of dots. */
  vec3 lat = emberWarp(wpos, 0.2, 15.0) * 0.07;
  vec3 cell = floor(lat);
  float h = emberHash(cell);
  float h2 = fract(h * 197.13);
  float fine = emberHash(floor(wpos * 0.26) + 53.0);
  /* A COAL IS A BLOB IN ITS CELL, NOT THE CELL. Lighting the whole cell
     makes every coal the same axis-aligned rectangle and every one of
     them the same size, which on a ceiling seen down its own length is a
     tiling pattern. Falling off from the middle of the cell gives it a
     round edge, a dark gap between it and its neighbour, and — because
     the radius is the cell's own hash — a SIZE, which is the detail that
     makes a scatter of them read as coals of different ages. */
  vec3 off = fract(lat) - 0.5;
  float blob = 1.0 - smoothstep(0.34 + h2 * 0.16, 0.58 + h2 * 0.16, length(off));
  /* And they fade out with distance for the same reason. A coal is a
     small bright thing; small bright things at three thousand units are
     one pixel of aliasing each. */
  float near = 1.0 - smoothstep(700.0, 2000.0, depth);
  if (near <= 0.001) return vec3(0.0);
  /* a scatter, in the DARK parts — coals live in the recesses, and a
     burnt texture's own dark places are exactly those recesses */
  float dark = 1.0 - smoothstep(0.07, 0.34, lum);
  float sit = smoothstep(0.88 - charAmt * 0.07, 0.975 - charAmt * 0.04, h) * dark * near * blob;
  /* the sparks: a third the size, a third as many, and gone by a
     thousand units — a one-pixel bright thing at range is aliasing */
  float grit = 1.0 - smoothstep(300.0, 1000.0, depth);
  sit += smoothstep(0.986 - charAmt * 0.012, 0.999, fine) * dark * grit * 0.55;
  sit = min(sit, 1.2);
  if (sit <= 0.001) return vec3(0.0);
  /* Two sines beaten against each other so neighbouring coals are out of
     step — the trees' trick, and the reason a burnt surface breathes
     instead of pulsing all at once. */
  float flick = 0.70 + 0.36
    * sin(emberTime * 9.0 + h * 31.4 + wpos.y * 0.17)
    * sin(emberTime * 3.7 + h2 * 12.0 + wpos.x * 0.11);
  float heat = clamp(sit * (0.45 + 0.75 * charAmt), 0.0, 1.0);
  /* AND THE PALETTE CYCLE, quantised to whole steps of the ramp so it
     flips between real colours instead of sliding through the gaps.

     BIASED DOWN THE RAMP, which is the difference between a coal and a
     speck of confetti. The top of the ember ramp is #f8d0a0 — a pale
     warm cream, correct for the white-hot heart of a fire and nothing
     like the colour of a coal in a burnt-out aisle. heat lands near 1 on
     anything fully charred, so the index clamped at the top and every
     coal in the store came out the same pale tan: brighter, yes, and
     reading as litter rather than as fire. Two thirds of the way is
     #985800 to #c07820, which is what a coal is, and the wave still
     takes the odd one to the top and back. */
  float ph = emberTime * 0.9 + h * 6.28 + h2 * 2.1;
  float wave = abs(fract(ph) * 2.0 - 1.0) - 0.5;
  float idx = clamp(heat * 0.60 + wave * 0.46, 0.0, 1.0);
  /* AND THEY ARE BRIGHTER. 0.55 was set against a CHARRED surface at a
     lit region's own light. A gutted one is darker, further through, and
     lit by nothing but this — so the one thing left in the room that is
     still a fire was the one thing that had not been turned up. */
  return emberRamp[int(floor(idx * 7.0 + 0.5))] * (heat * flick * 1.45);
}

/* ---------------------------------------------------------------------
   A REGION BEING BURNT, RATHER THAN HAVING BEEN

   How burnt the piece of floor under this pixel is, read out of the
   fire's own cell grid. Off the edge of the fire's world — a sprite in
   the woods, anything the grid does not cover — is zero rather than the
   clamped edge value, or the far wall of the car park would soot itself
   from whatever the last cell of the shop was doing.
   ------------------------------------------------------------------- */
float burnAt(vec3 w) {
  /* The renderer's z runs BACKWARDS against the map's y — see addQuad in
     js/mapgeo.js — so the grid is indexed with -z. */
  vec2 c = (vec2(w.x, -w.z) - burnOrigin) / burnCell;
  if (c.x < 0.0 || c.y < 0.0 || c.x > burnCols || c.y > burnRows) return 0.0;
  return texture2D(burnGrid, (c + 0.5) / vec2(burnCols, burnRows)).r;
}

/* ---------------------------------------------------------------------
   SOOT, WHICH ARRIVES BEFORE THE FIRE DOES

   The thing a burning shop does that this game was not drawing: it goes
   BLACK, gradually, in patches, starting at the corners and the joints,
   long before anything in it has actually burnt. Two texture swaps — one
   at half the region's fuel and one at nearly all of it — cannot say
   that, and the first half of every region's life was therefore
   invisible: an aisle lost half its stock without a pixel changing and
   then changed all at once.

   WHERE IT LANDS FIRST is a world-space field, two scales of it: cells
   about a shelf bay across decide which patches go early, and cells a
   few units across ragged the edge of each one. So the soot has a SHAPE
   of its own rather than a level of its own, and it spreads across a
   wall as the region's number climbs — the lowest-numbered cells first,
   joining up, until the wall is black. Nothing about it is per-region
   except the number, so two aisles burning at once are never in step,
   because they are not in the same place.

   AND THE EDGE CRAWLS, on the coals' own clock, which is what makes a
   wall halfway through catching still be doing something while you look
   at it. The advancing edge is also the only part of it that is HOT: a
   scorch mark is orange at its rim and dead black behind it, which is
   one line of arithmetic (the product of the amount and its complement,
   which peaks exactly where the boundary is) and is the difference
   between soot spreading and a texture fading.

   It costs nothing where nothing has burnt, which is most of the game
   and all of it until you do something.
   ------------------------------------------------------------------- */
float sootAmount(float burn, vec3 wpos) {
  /* Up over the region's first two fifths, and then OUT again as the
     charred textures arrive at the halfway mark and take the job over.
     Both are driven by the same number, so the hand-off cannot drift. */
  float pre = smoothstep(0.015, 0.40, burn) * (1.0 - smoothstep(0.44, 0.58, burn));
  if (pre <= 0.002) return 0.0;
  /* THREE SCALES OVER A WARPED LATTICE — see emberPatch. Two scales of
     plain floor() is a chequerboard of soot. */
  float h = emberPatch(wpos);
  float crawl = 0.05 * sin(emberTime * 0.55 + h * 26.0)
              + 0.03 * sin(emberTime * 0.19 + h * 7.3);
  /* and a TIGHTER ramp from clean to black: 0.26 spread the transition
     over a third of the field, so most of a burning wall sat at halfway
     sooty and the boundary was a gradient rather than a front. */
  return clamp((pre * 1.3 - h + crawl) / 0.17, 0.0, 1.0);
}

vec3 sootOn(vec3 c, float soot, vec3 wpos) {
  if (soot <= 0.002) return c;
  /* Soot is not a grey filter. It is carbon: it takes the colour out
     first and the brightness after, so a red fascia goes brown and then
     black rather than pink and then grey.

     HOW DARK IS NOT A MATTER OF TASTE, it is a matter of matching what
     this hands over to. At half a region's fuel the charred textures
     arrive, and charVariant in js/textures.js keeps between a third and
     four fifths of every pixel and then puts pale ash over the top of
     it — deliberately, twice over, because a burnt store dark enough to
     be accurate is a store you cannot walk back out of. The first cut of
     this took the albedo to a fifth, which the room light then took to
     nothing, and a 40%-burnt aisle was a black void with shoppers
     floating in it. So it keeps about half, patchily, and gets its own
     ash for the same reason the textures have theirs. */
  float lum = dot(c, vec3(0.2126, 0.7152, 0.0722));
  /* the ash gets a patch field of its own, warped for the reason the
     soot is: eleven-unit cubes of pale grey on a floor is graph paper */
  vec3 aw = emberWarp(wpos, 0.14, 11.0);
  float h2 = emberHash(floor(aw * 0.09) + 7.0) * 0.7
           + emberHash(floor(aw * 0.30) + 17.0) * 0.3;
  float keep = 0.38 + h2 * 0.22;
  vec3 burnt = mix(c, vec3(lum), 0.55) * keep + vec3(0.022, 0.018, 0.015);
  vec3 out_ = mix(c, burnt, soot);
  /* the ash, pale and patchy, which is the only thing you can see the
     shape of a sooty wall by */
  out_ += vec3(0.062, 0.058, 0.055) * smoothstep(0.62, 0.97, h2) * soot;
  /* AND THE RIM, which is the only part of it still alight and was the
     part doing the least work. The product of the amount and its
     complement peaks exactly at the boundary; SQUARED, it peaks in a
     band a third as wide, which turns a warm wash over half the patch
     into a LINE of fire creeping across it — and a line can be several
     times brighter than a wash without washing anything out.

     Two colours on it, because a burning edge is not one temperature: a
     broad orange shoulder, and a pale core that only the very boundary
     reaches. */
  float rim = soot * (1.0 - soot) * 4.0;
  float edge = rim * rim;
  float core = edge * edge;
  float flick = 0.72 + 0.34 * sin(emberTime * 7.0 + wpos.x * 0.09 + wpos.y * 0.13)
                     * sin(emberTime * 2.3 + wpos.z * 0.07);
  return out_ + (vec3(0.62, 0.19, 0.030) * edge + vec3(0.55, 0.40, 0.16) * core) * flick;
}

/* WHEN THE STREET LAMPS ARE ON, off the sky's light: they come on as
   the sky goes under a half and are full by the time it is at a fifth,
   which is dusk to dark and dark to dawn — and a storm dark enough to
   trip a photocell. The same curve is in js/lamplight.js (lampsOn
   there), so the flare over a lamp and the pool under it switch
   together. */
float lampsOn(float sl) { return 1.0 - smoothstep(0.22, 0.50, sl); }

float worldBand(float lightIn, float depth, float sky, float fullbright) {
  /* Distance diminishing. Linear in depth, because Doom's was too, and
     because an inverse-square falloff in a corridor lit by nothing in
     particular just looks broken.

     Under the sky the same curve is stretched and its floor lifted, so
     the far end of the car park stays a car park. */
  float fall = lightFalloff * mix(1.0, 3.4, sky);
  float mn   = min(0.85, minLight + 0.32 * sky);
  /* WHAT THE SKY ADDS. The vertex's own light is the floor — it was
     written for two in the morning and two in the morning must not
     change — and the sky lifts it, by however much of this surface's
     light comes from the sky. Indoors that is nothing. Under a canopy
     it is half. In the car park at dawn it is the dawn. And a lit sky
     does not diminish with distance the way a fitting does, so the
     floor of the falloff comes up with it. */
  float li = mix(lightIn, max(lightIn, skyLight), sky);
  mn = mix(mn, 1.0, clamp(skyLight, 0.0, 1.0) * sky);
  float dim = 1.0 - clamp(depth / fall, 0.0, 1.0);
  float l = li * mix(mn, 1.0, dim) * globalLight;

  /* THE STEP. 32 levels, same as Doom's 32 colormaps. Everything above is
     continuous maths; this is the line that makes it look right. */
  l = floor(l * 32.0 + 0.5) * (1.0 / 32.0);
  return mix(l, 1.0, fullbright);
}

/* ---------------------------------------------------------------------
   HOW WARM A SURFACE IS, for the thermal sight — see world.thermal

   A NIGHT IN ONE NARROW BAND. Everything that is not a source sits low
   and close together: a little warmer for darker paint (it held more of
   the day), a little for the light that is falling on it (a lamp is a
   heater as well), so a street still reads as a street and the eye goes
   straight past it to whatever is not in the band. The fire and the
   beam warm what is near them on the same falloff they light it by;
   anything that is its own light — the fire, a lamp, a flare — is the
   hottest thing there is; and the air takes the far distance down to
   the cold of the sky, which is how a real sensor loses contrast with
   range. No smoke: seeing through smoke is what a thermal sight is for.
   ------------------------------------------------------------------- */
float thermalOf(vec3 albedo, float l, float depth, vec3 world, float fullbright) {
  float lum = dot(albedo, vec3(0.2126, 0.7152, 0.0722));
  float h = 0.13 + 0.07 * (1.0 - lum) + 0.09 * lum * lum + 0.06 * clamp(l, 0.0, 1.0);
  if (fireLight > 0.0) {
    float fa = clamp(1.0 - distance(world, fireLightPos) / fireLightRange, 0.0, 1.0);
    h += fa * fa * fireLight * 0.45;
  }
  if (beam > 0.0) {
    vec3 rel = world - beamPos;
    float along = clamp(dot(rel, beamDir), 0.0, beamLen);
    float ba = clamp(1.0 - distance(rel, beamDir * along) / beamRange, 0.0, 1.0);
    h += ba * ba * beam * 0.5;
  }
  h = mix(h, 1.0, fullbright);
  float at = clamp((depth - airNear) / max(1.0, airFar - airNear), 0.0, 1.0);
  return mix(h, 0.06, at * at * 0.85);
}

vec3 worldShade(vec3 albedo, float l, float depth, vec3 world, float fullbright) {
  if (thermal > 0.5) return vec3(thermalOf(albedo, l, depth, world, fullbright));
  /* the map's light colour on the sector's light, and the ambient light
     on top of both — see world.lightColor */
  vec3 c = albedo * l * tint * lightColor;
  c += albedo * ambientColor * (1.0 - fullbright);

  /* Firelight, added on top of the banded light rather than folded into
     it — a smooth glow crossing the steps is what a real light in a
     stepped-lighting room looks like. Falls off as the square of the
     distance and is clamped, so standing in it does not blow out to
     white. */
  if (fireLight > 0.0) {
    float fd = distance(world, fireLightPos);
    float fa = clamp(1.0 - fd / fireLightRange, 0.0, 1.0);
    fa *= fa;
    c += albedo * fireLightColor * (fa * fireLight * (1.0 - fullbright * 0.7));
  }

  /* THE BEAM, and it is a line and not a point — see the note on
     beamPos. Distance to the nearest point on the segment, squared
     falloff like the fire's, and then the differential flicker: a hash
     of the fragment's own place on a coarse grid picks both the RATE
     and the PHASE of its wobble, so no two surfaces near the column are
     doing the same thing at the same time and none of them is doing it
     at the frame rate. */
  if (beam > 0.0) {
    vec3 rel = world - beamPos;
    float along = clamp(dot(rel, beamDir), 0.0, beamLen);
    float off = distance(rel, beamDir * along);
    float ba = clamp(1.0 - off / beamRange, 0.0, 1.0);
    ba *= ba;
    float n = fract(sin(dot(floor(world * 0.017), vec3(12.9898, 78.233, 37.719))) * 43758.5453);
    float flick = 0.62 + 0.38 * sin(beamSeed * (4.0 + n * 9.0) + n * 31.4);
    c += albedo * beamColor * (ba * beam * flick * (1.0 - fullbright * 0.5));
    /* and a hard white core to it very close in, which is what stops a
       wall a metre from the column reading as merely green */
    c += beamColor * ba * ba * beam * 0.22 * flick;
  }

  /* THE AIR. The fog colour is a texel of the sky: the horizon row of
     the sky bake, in the direction this fragment lies from the eye.
     The azimuth formula is the sphere's own (js/skyart.js, header) —
     atan2(z, x) over a full turn in the renderer's axes. Nearest
     filtered and repeat-wrapped, so a negative u is fine and the fetch
     is one texel from a megapixel texture that lives in cache. Half a
     texel above the horizon, in the bake's own row count (SKY_H), so
     the row is the first one over the line whatever size the sky is.
     A smooth ramp rather than a straight one, so the air starts gently
     and a wall does not read as crossing a line. */
  vec3 toFrag = world - eyePos;
  float az = atan(toFrag.z, toFrag.x) * 0.15915494;          // over 2 pi
  vec3 air = texture2D(skyTex, vec2(az, 0.5 + 0.5 / ${SKY_H}.0)).rgb;
  /* or the map's own colour for it (the fog colour override) */
  air = mix(air, airColor, airOverride);
  float at = clamp((depth - airNear) / max(1.0, airFar - airNear), 0.0, 1.0);
  at = at * at * (3.0 - 2.0 * at);
  c = mix(c, air, at);

  /* SECTOR FOG, GZDoom's way: the fog of the sector a surface is in —
     its colour, and a density, 0 to 100, at which the fog is half-way
     in at 25600/density units (100: at 256; 10: at 2560) — or the map's
     default fog for what has no sector (a sprite, a tree). Its colour is
     lit by the map's light colour, and the ambient light is in it too,
     by fogAmbient: a fog is air with light in it. Not in fullbright,
     which is for looking at the textures. */
  #ifdef SECTOR_FOG
    vec4 fg = vFog.a < 0.0 ? fogDefault : vFog;
  #else
    vec4 fg = fogDefault;
  #endif
  if (fogMarch > 0.5) {
    /* some sector has fog of its own: follow it along the line of sight
       (FOG_GLSL), so it fades from sector to sector */
    #ifndef SECTOR_FOG
      fg = fogAirAt(world);
    #endif
    vec4 fa = fogAlong(eyePos, world, fg);
    c = mix(c * fa.a + fa.rgb, c, fullbright);
  } else if (fg.a > 0.0) {
    float ff = (1.0 - exp2(-depth * fg.a / 25600.0)) * (1.0 - fullbright);
    vec3 fc = fg.rgb * lightColor + ambientColor * fogAmbient;
    c = mix(c, fc, ff);
  }

  /* THE SMOKE, after the air, because it is between you and everything.
     Multiplied by smokeDensity so a store that is not yet on fire has
     no haze at all rather than a permanent grey wash; and lit by the
     fire under it, not by the room — its floor sits well above the
     room's own light, or a burning store goes black. */
  float f = clamp((depth - smokeNear) / max(1.0, smokeFar - smokeNear), 0.0, 1.0) * smokeDensity;
  return mix(c, smokeColor * max(l, 0.7), f);
}
`;

const COMMON_VERT = /* glsl */`
/* DOOM 64'S COLOURED LIGHT: what colour the light falling on this
   surface is, multiplied into its picture. White everywhere unless a
   map says otherwise — see TINT below, and the sector colours MEWD Editor
   sets (js/editor/). */
varying vec3  vTint;
varying vec4  vFog;
#ifdef TINT
  attribute vec3 tintRGB;
  /* and the fog of the sector the surface is in: rgb, density, or a
     density of -1 for the map's default */
  attribute vec4 fogRGBA;
#endif
varying vec2  vUv;
varying float vLight;
varying float vDepth;
varying vec3  vWorld;
varying float vSky;
varying float vChar;
varying float vLamp;

#ifdef PER_VERTEX_LIGHT
  attribute float light;
  /* HOW MUCH OF THIS SURFACE'S LIGHT COMES FROM THE SKY.

     Doom diminished everything by distance at one rate, which is right
     for a corridor lit by fittings and wrong the moment a level has a
     six-thousand-unit car park in it: the far end of the parade came out
     as a black mass, because the far end of a CORRIDOR should. Outside,
     the source is the sky, it is behind you as well as in front of you,
     and it does not run out at any distance you can walk.

     So this is a property of the surface, not a global: 1 outdoors, 0
     indoors, and in between under a canopy — which is exactly what a
     canopy is. It stretches the falloff and lifts its floor, and nothing
     indoors changes at all. */
  attribute float sky;
  /* how burnt this surface's region is: 0 untouched, about a half
     charred, 1 gutted. Set by js/mapgeo.js, read by emberOf. */
  attribute float charred;
  /* whether this surface is lit by a STREET LAMP: 1 on the pool of
     pavement under one and on the lamp's own post, 0 everywhere else.
     Set by js/mapgeo.js; what it does is in the fragment shader. */
  attribute float lamp;
#else
  uniform float light;
  uniform float sky;
  uniform float charred;
  uniform float lamp;
#endif

#ifdef INK
  /* WHAT A SURFACE WITH NO PICTURE IS PAINTED, per vertex: rgb is the
     colour its own glTF material declared as baseColorFactor and a is 1
     where it applies, 0 where the texture does. A model is usually a
     handful of materials and only one of them is a sheet — the van's
     glass, tyres, bumpers and chassis are a flat near-black — and a
     second material would be a second draw call for every slab of cars.
     This is that second material, carried in the vertices instead.

     baseColorFactor is LINEAR, and an sRGB texture is decoded to linear
     when it is sampled, so the two sides of the mix are already in the
     same space and neither needs converting. */
  attribute vec4 ink;
  varying vec4 vInk;
#endif

#ifdef BILLBOARD
  uniform float billboardRot;    // yaw the quad is turned to, in world space
  uniform vec2  spriteScale;     // width, height in world units
  uniform vec2  spriteOffset;    // x nudge, y lift off the floor
#endif

#ifdef INSTANCED_SPRITE
  /* ------------------------------------------------------------------
     A CROWD IN ONE DRAW CALL

     Every standee used to be its own mesh with its own material, so the
     eight hundred people you can see across a car park were eight
     hundred draw calls and eight hundred uniform updates a frame. They
     share twenty-eight pictures between them — a shopper is one drawing
     that faces every way (see js/spriteload.js) — so they can be
     twenty-eight draw calls instead, which is what js/standees.js does.

     WHAT WAS A UNIFORM IS NOW AN ATTRIBUTE, and that is the whole of
     the difference. The four values the fragment shader reads per
     sprite — how fullbright it is, how frozen, how far through being
     eaten, how alight — are declared below as VARYINGS under this same
     define, with the names they already had. Not one line of the body
     of either shader changes, which is the point: a crowd drawn this
     way cannot look different from a crowd drawn the other way,
     because the code that draws it is the same code.
     ------------------------------------------------------------------ */
  attribute vec3  iPos;        // where its foot is, in renderer axes
  attribute vec2  iSize;       // width and height in world units
  attribute float iLight;      // the light of the region it stands in
  attribute float iSky;        // how much of that light is the sky's
  attribute vec4  iFlags;      // fullbright, frost, ash, alight
  attribute vec3  iTint;       // the colour of the light it stands in
  attribute vec4  iFog;        // the fog it stands in, eased; density -1: the grid's
  /* the yaw every sprite in the scene is turned to, which is the one
     thing here that IS the same for the whole batch. Declared again
     because a standee material does not define BILLBOARD. */
  uniform float billboardRot;
  varying float fullbright;
  varying float frost;
  varying float ash;
  varying float alight;
#endif

${SECTOR_GRID_GLSL}

void main() {
  vUv = uv;
  vTint = vec3(1.0);
  vFog = vec4(0.0, 0.0, 0.0, -1.0);
  #ifdef TINT
    vTint = tintRGB;
    vFog = fogRGBA;
  #endif
  vLight = light;
  vSky = sky;
  vChar = charred;
  vLamp = lamp;
  #ifdef INK
    vInk = ink;
  #endif

  vec3 p = position;

  #ifdef BILLBOARD
    /* The quad is authored as a unit square with its foot at y=0. Scale it,
       nudge it, then spin it about Y only — never about X. A Doom sprite
       stays bolt upright however far you are looking up or down; tilting it
       to face the camera properly is the one "improvement" that instantly
       stops it looking like Doom. */
    p.x *= spriteScale.x;
    p.y *= spriteScale.y;
    p.x += spriteOffset.x;
    p.y += spriteOffset.y;
    float c = cos(billboardRot), s = sin(billboardRot);
    p = vec3(p.x * c, p.y, -p.x * s);
  #endif

  #ifdef INSTANCED_SPRITE
    /* the same quad, the same spin, and the instance's own everything —
       see the block at the top of this file */
    vLight = iLight;
    vSky = iSky;
    vTint = iTint;
    fullbright = iFlags.x; frost = iFlags.y; ash = iFlags.z; alight = iFlags.w;
    p.x *= iSize.x;
    p.y *= iSize.y;
    float ic = cos(billboardRot), is = sin(billboardRot);
    p = vec3(p.x * ic, p.y, -p.x * is) + iPos;
  #endif

  vec4 wp = modelMatrix * vec4(p, 1.0);
  vWorld = wp.xyz;
  vec4 mv = viewMatrix * wp;
  vDepth = -mv.z;
  gl_Position = projectionMatrix * mv;

  /* A THING IN A SECTOR, in a map from the editor: lit, coloured and
     fogged by the sector its foot is in (world.sectorA). Level geometry
     (TINT) carries its own per vertex. A standee is already handed its
     sector's light and colour by the game, so it takes the fog; a model
     takes all three, its own shading times the sector's light. */
  #ifndef TINT
    if (sectorOn > 0.5) {
      #ifdef INSTANCED_SPRITE
        vec3 foot = iPos;
      #else
        vec3 foot = (modelMatrix * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
      #endif
      vFog = sectorFogAt(foot);
      #ifdef INSTANCED_SPRITE
        /* a thing that moves hands in its own fog, eased across the
           boundary it has just crossed (tweenLook, js/sectorgrid.js) */
        if (iFog.w >= 0.0) vFog = iFog;
      #endif
      #ifndef INSTANCED_SPRITE
        vec4 sl = sectorLightAt(foot);
        vLight *= sl.a;
        vTint *= sl.rgb;
      #endif
    }
  #endif
}
`;

const COMMON_FRAG = /* glsl */`
varying vec3 vTint;
/* the sector's fog, per vertex, or alpha -1 for the map's default —
   see SECTOR FOG in worldShade */
#define SECTOR_FOG
varying vec4 vFog;
uniform sampler2D map;
uniform float alphaTest;
#ifdef INSTANCED_SPRITE
  /* per instance rather than per draw — see the INSTANCED_SPRITE block in
     the vertex shader. The NAME is the same on purpose, so that not one
     line of the body below knows which it is reading. */
  varying float fullbright;
#else
  uniform float fullbright;    // 1.0 = ignore distance and sector light entirely
#endif
${WORLD_UNIFORMS_GLSL}

varying vec2  vUv;
varying float vLight;
varying float vDepth;
varying vec3  vWorld;
varying float vSky;
varying float vChar;
varying float vLamp;

/* the street lamps' colour — see LAMP_LIGHT at the top of this file */
const vec3 LAMP_LIGHT = vec3(${LAMP_LIGHT.map(v => v.toFixed(3)).join(', ')});

#ifdef INK
  varying vec4 vInk;
  /* HOW WARM THIS VEHICLE IS, for the thermal sight only: its engine
     running, per material, set by js/thermal.js on the frames it draws */
  uniform float warmth;
#endif
#ifdef INSTANCED_SPRITE
  /* and whether this picture is a BODY — a person, not a trolley. One
     batch is one picture, and a picture is one kind of thing, so this
     is per batch; js/standees.js sets it from the actor */
  uniform float warm;
#endif

#ifdef FROST
  /* HOW FROZEN THIS THING IS, 0 to 1, per sprite. Only the actors ask
     for it, so the walls and the floor never carry the branch. */
  #ifdef INSTANCED_SPRITE
    varying float frost;
  #else
    uniform float frost;
  #endif
  /* AND HOW FAR THROUGH BEING EATEN BY THE FIRE, on the same terms and
     under the same define, because the two are the same kind of fact
     about the same kind of thing and a second define is a second shader
     permutation for one uniform. See the ASH block in main(). */
  #ifdef INSTANCED_SPRITE
    varying float ash;
  #else
    uniform float ash;
  #endif
  /* AND HOW ALIGHT, 0 to 1. Not the same fact as the one above: ash is
     a body being consumed and ends in a heap, this is a person running
     with their coat on fire and ends in a bang. A thing is never both.
     (No backticks in here, ever: this is a template literal, and one
     of those inside it ends the shader in the middle of a sentence.) */
  #ifdef INSTANCED_SPRITE
    varying float alight;
  #else
    uniform float alight;
  #endif
#endif

${WORLD_SHADE_GLSL}

void main() {
  vec4 t = texture2D(map, vUv);
  /* WHAT A THING THAT IS ITSELF ON FIRE ADDS, held out here so the one
     line at the bottom that adds it does not need the define.

     ADDED AND NOT MIXED, which is the whole reason a person on fire
     reads as one. Every colour in the ember ramp is at most white, so a
     colour MAP alone can never make a burning shopper brighter than a
     fully lit one — and what came out of that was a person the colour
     of terracotta standing in a dark aisle. Fire is a SOURCE. The coals
     on a burnt wall have been added rather than mixed since the day
     they went in (see emberOf); this is the same argument about a
     person. */
  vec3 glowAdd = vec3(0.0);
  #ifdef INK
  /* ------------------------------------------------------------------
     WHAT THIS SURFACE IS PAINTED, in the two senses a vehicle needs,
     and the alpha channel says which:

       a = 1   the surface has no picture at all and vInk.rgb IS its
               colour — the second material, carried in the vertices
               rather than costing a second draw call
       a = 0   the surface has a picture, and vInk.rgb is what the WHITE
               PAINT in that picture is multiplied by

     THE SECOND SENSE IS HOW A CAR PARK GETS MORE THAN ONE COLOUR OF
     VAN. There is one model, one texture and one mesh for the whole lot
     — seventy-seven vehicles in a single draw call, which is the thing
     worth keeping — so a red van cannot be a different file or a
     different sheet. It has to be the same texel, multiplied.

     AND THE MASK IS READ OUT OF THE TEXEL ITSELF rather than painted
     into the sheet by hand. The van's own paint is white: bright and
     dead neutral. Everything that must NOT take the colour — the
     grille, the bumpers, the tyres, the glass — is far darker. So a
     luminance ramp with a saturation guard isolates the bodywork
     exactly, and it does it per TEXEL, which is the whole reason this
     looks like paint: every bit of shading the artist put in the sheet
     survives, so the shadowed flank of a blue van is dark blue and the
     lit roof is bright blue. Painting a flat colour over the body would
     have thrown all of that away.

     THE NUMBERS ARE IN LINEAR AND THAT IS THE WHOLE TRAP. The sheet is
     an sRGB texture and is decoded on the way out of texture2D, so what
     arrives here is NOT what a colour picker says about the PNG. The
     thresholds were first set off the file — paint at 0.75 to 0.94,
     ramp from 0.55 — and in linear the paint is 0.50 to 0.78, so the
     ramp caught only the brightest highlights: what came out was a
     white van with a red pinstripe down every edge, which is a good
     picture of getting a colour space wrong. Measured in linear, on the
     file: background 0.06, tyres and grille under 0.09, glass 0.28,
     the darkest shadowed paint 0.53, a lit panel 0.67, the roof 0.78.
     The ramp sits in the gap between the glass and the shadow.

     MULTIPLIED, NOT MIXED. White times red is red; light grey times red
     is a darker red. Which is what paint does.
     ------------------------------------------------------------------ */
    t = mix(t, vec4(vInk.rgb, 1.0), vInk.a);
    if (vInk.a < 0.5) {
      float pl = dot(t.rgb, vec3(0.30, 0.59, 0.11));
      float pmx = max(t.r, max(t.g, t.b)), pmn = min(t.r, min(t.g, t.b));
      float ps = pmx > 0.0 ? (pmx - pmn) / pmx : 0.0;
      float pm = smoothstep(0.32, 0.52, pl) * (1.0 - smoothstep(0.06, 0.14, ps));
      t.rgb = mix(t.rgb, t.rgb * vInk.rgb, pm);
    }
  #endif
  if (t.a < alphaTest) discard;
  /* AND WHETHER IT IS FROZEN SOLID.

     A COLOUR MAP AND NOT A TINT, for the same reason the gun's cold
     plume is not a tint: multiplying a shopper's red coat by blue gives
     a dark muddy coat, and what a person inside a block of ice looks
     like is not their own colours dimmed — it is their SHAPE, in ice.
     So the texel's luminance is kept and everything else is thrown
     away, and that one number is run up a ramp from a deep shadowed
     blue to a pale lit one. A red coat and a green coat come out as the
     same ice at different brightnesses, which is exactly what they
     should do.

     The exponent is under one so the midtones lift: skin and a dark coat
     are close together in luminance and would otherwise both land in the
     bottom of the ramp and read as a silhouette. */
  #ifdef FROST
  if (frost > 0.0) {
    float lum = dot(t.rgb, vec3(0.30, 0.59, 0.11));
    vec3 ice = mix(vec3(0.09, 0.17, 0.31), vec3(0.74, 0.93, 1.05), pow(lum, 0.62));
    t.rgb = mix(t.rgb, ice, frost);
  }

  /* ------------------------------------------------------------------
     A PERSON ON FIRE

     THE FLAMES ARE NOT ENOUGH ON THEIR OWN. Licks of fire thrown off a
     burning shopper (see Effects.bodyFire) put fire in front of them
     and leave a trail behind them, and with the drawing untouched
     underneath what the eye reads is a shopper standing BEHIND a fire.
     What makes it that person burning is that their own colours go.

     A MAP AND NOT A TINT, exactly as the ice is and for exactly the
     same reason: multiplying a green coat by orange gives a muddy
     brown coat, and what somebody on fire looks like is their SHAPE in
     flame. So the texel's luminance is kept, everything else is thrown
     away, and that one number picks a colour off the ember ramp — the
     same eight the coals in a burnt aisle use, so a person burning and
     the aisle they set light to are made of the same paint.

     HOTTEST AT THE FEET, because fire climbs: a person alight is white
     at the knees and their head is the last thing still recognisable.
     That gradient is also what keeps them readable as a PERSON for the
     four seconds they have left — a figure evenly washed to orange is
     a silhouette, and the whole point of them running is that you can
     see who it is running.

     AND THEY DARKEN UNDERNEATH IT. The base colour is taken down as
     the fire takes hold, so what is not actually alight at this
     instant is scorched cloth rather than a clean coat — and the
     flicker moves the line between the two about, which is the
     difference between a burning person and a person painted orange.
     ------------------------------------------------------------------ */
  if (alight > 0.0) {
    float lum = dot(t.rgb, vec3(0.30, 0.59, 0.11));
    float n = emberHash(vec3(floor(vUv * vec2(11.0, 17.0)), 3.0));
    /* two beats against each other, so the fire on one shopper is not
       in step with the fire on the next one along */
    float fl = 0.72 + 0.28 * sin(emberTime * 13.0 + n * 29.0)
                          * sin(emberTime * 5.3 + vUv.y * 21.0);
    /* 1 at the feet and 0 at the crown — see the note in the ash block
       on which way vUv.y points */
    float low = 1.0 - vUv.y;
    float heat = alight * clamp(0.55 + low * 0.75, 0.0, 1.3) * fl;
    /* BIASED DOWN THE RAMP, which is the same lesson the coals on a
       burnt wall had to learn. The top of the ember ramp is a pale warm
       cream — correct for the white heart of a fire and nothing like a
       person on fire — and luminance alone put most of a shopper up
       there, so what came out was a bronze statue. Luminance carries
       the SHAPE and the heat carries the COLOUR: deep red at the head,
       yellow at the knees, and the flicker walking the line about. */
    float idx = clamp(lum * 0.50 + heat * 0.46 + n * 0.10, 0.0, 1.0);
    vec3 flame = emberRamp[int(floor(idx * 7.0 + 0.5))];
    float take = clamp(heat, 0.0, 1.0);
    t.rgb = mix(t.rgb * (1.0 - 0.55 * alight), flame, take);
    /* and the light they throw, on top of everything the room does to
       them — most of it at the knees, where the fire is */
    glowAdd += flame * take * (0.34 + 0.52 * low) * alight;
  }

  /* ------------------------------------------------------------------
     A PERSON BEING EATEN BY THE FIRE

     Somebody who was frozen when the flame reached them does not melt
     and run; they are consumed where they stand and collapse into a
     heap (see Actor.burnAway). This is the whole of what that looks
     like, and it is done in the shader rather than in art because
     seventeen shoppers times an animation of a person burning away is
     art nobody is going to draw, and because the drawing being EATEN —
     their own coat, their own shape, going — is the part that makes it
     read as that person rather than as an effect played over them.

     A FRONT, NOT A FADE. Every texel gets a threshold and the front is
     one number crossing all of them: below it the texel is gone,
     within a band of it the texel is a coal, and above it the texel is
     still there but scorched by the heat coming. Three zones, one
     comparison, and what sweeps across is a ragged edge of fire rather
     than a person turning transparent.

     FROM THE FEET UP, which is not arbitrary: the fire is on the floor
     and fire goes up. Seven parts of the threshold are height and three
     are noise, so the edge is level enough to read as a front and torn
     enough not to read as a wipe. Two scales of noise, the coarse one
     about the size of a hand, because one scale is a repeating pattern
     at this resolution.

     AND THE COALS ARE ADDED, NOT MULTIPLIED, for the same reason the
     ones on a burnt wall are: they are the only light on a dark thing
     in a dark room, and a multiplied coal is a coal you cannot see.
     ------------------------------------------------------------------ */
  if (ash > 0.0) {
    float n = emberHash(vec3(floor(vUv * vec2(13.0, 19.0)), 0.0)) * 0.62
            + emberHash(vec3(floor(vUv * vec2(29.0, 41.0)), 7.0)) * 0.38;
    /* vUv.y RUNS UP THE PERSON: 0 at the foot of the quad, 1 at the top
       of their head. The quad is authored as a unit square with its
       foot at y = 0 (see the vertex shader) and its uv goes with it.
       The first cut of this assumed the opposite, wrote 1.0 - vUv.y,
       and ate people from the hat down — which reads as a person
       dissolving rather than as a person on fire, and was obvious in
       the first screenshot. Measured, not reasoned about: the flip was
       tried and looked at. */
    float up = vUv.y;                       // the foot of the sprite first
    float th = up * 0.70 + n * 0.30;
    /* A LINE, NOT A BELT. The threshold is seven parts height to three
       parts noise, so a band of 0.15 lit a fifth of the person at once
       and read as a bonfire they were standing in rather than as a
       front crossing them. */
    const float BAND = 0.10;                // how deep the line of coals is
    /* AND THE SCORCH AHEAD OF IT IS NARROW. At a quarter of the body it
       blackened everything above the flame line, so a shopper was a
       silhouette a second in and there was nothing left to watch being
       eaten. What has to stay legible is the person; what is burning is
       a line across them. */
    const float CHAR = 0.14;                // and how far ahead of it the scorch reaches
    float edge = ash * (1.0 + BAND * 2.0) - BAND;
    float g = th - edge;
    if (g < -BAND) discard;                 // this much of them is gone
    float hot = 1.0 - smoothstep(0.0, BAND, abs(g));
    float scorch = max(1.0 - smoothstep(0.0, CHAR, max(g, 0.0)),
                       1.0 - smoothstep(0.0, BAND, -min(g, 0.0)));
    t.rgb = mix(t.rgb, vec3(0.055, 0.048, 0.042), clamp(scorch, 0.0, 1.0) * 0.93);
    if (hot > 0.001) {
      /* the same palette cycle the coals on a burnt wall use, so a body
         going out and an aisle going out are the same fire */
      float fl = 0.60 + 0.40 * sin(emberTime * 11.0 + n * 37.0 + vUv.y * 9.0);
      float idx = clamp(0.42 + hot * 0.40 + fl * 0.20, 0.0, 1.0);
      /* squared, so the hot core is thin and the edges of the band fall
         away into the scorch instead of the whole band being white */
      glowAdd = emberRamp[int(floor(idx * 7.0 + 0.5))] * hot * hot * (0.9 + 0.6 * fl);
    }
  }
  #endif
  /* HOW BURNT THE FLOOR UNDER THIS PIXEL IS, continuously. The soot goes
     on the ALBEDO, before the light and before the smoke, because that
     is where it is: a wall with soot on it is a darker wall, and it
     diminishes down an aisle and catches the firelight exactly as the
     wall does. Adding it afterwards would have made a sooty wall in the
     dark end of aisle nine darker than the air in front of it.

     AND ONLY A SURFACE GETS IT, which is the fix for a bug that had been
     running quietly since the soot went in. Everything in this game
     shares one fragment shader, and this block asks the burn grid "how
     burnt is the floor HERE" — which for a wall is the right question
     and for a THING standing on that floor is not. Every sprite in the
     store was being given the soot and the live coals of whatever it
     happened to be standing over: shoppers with embers crawling on them,
     giblets stained, and most visibly the smoke, which is thirty units
     up in the air and was wearing the coals of the fire underneath it
     and shedding them as it drifted. A drifting sprite samples a
     different part of the grid every frame, so the coals CRAWLED.

     So it is a define now, and only the wall material sets it. Walls,
     floors, ceilings, the ruined roof steel and the vehicles are
     surfaces and burn; sprites are things standing in front of them. */
  #ifdef SURFACE_BURN
    float burn = burnAt(vWorld);
    float soot = sootAmount(burn, vWorld);
    vec3 albedo = sootOn(t.rgb, soot, vWorld);
  #else
    float burn = 0.0;
    vec3 albedo = t.rgb;
  #endif
  /* THE POOL UNDER A STREET LAMP IS A COLD LIGHT. A sector has one light
     and it is a number, so the pool of pavement under a lamp is a
     brighter sector and that is all the map can say. What it cannot say
     is what COLOUR the light is, and a mercury-vapour lamp's is not the
     sky's: it is the cold green-white the flare over it is drawn in. So
     a surface the map marks as lamp-lit — the pool, and the lamp's own
     post — has its albedo tinted by it, only after dark (by day the sky
     lifts the pavement to full and the lamp is off), and ahead of the
     banding so it steps with everything else. */
  albedo *= mix(vec3(1.0), LAMP_LIGHT, vLamp * lampsOn(skyLight));
  /* and the colour of the light itself, Doom 64's way: a sector's floor,
     ceiling and things each have one, and its walls run from one colour
     at the top to another at the bottom */
  albedo *= vTint;
  float l = worldBand(vLight, vDepth, vSky, fullbright);
  vec3 c = worldShade(albedo, l, vDepth, vWorld, fullbright);
  /* The coals go on AFTER the smoke, so a burnt aisle glows through it —
     and they arrive on how burnt the floor there is rather than on the
     sector's stage, so the first few show up in the recesses while there
     is still stock on the shelves and they thicken from there. */
  #ifdef SURFACE_BURN
    c += emberOf(max(vChar, smoothstep(0.06, 0.92, burn)), vWorld,
                 dot(albedo, vec3(0.2126, 0.7152, 0.0722)), vDepth);
  #endif
  /* ------------------------------------------------------------------
     THE THERMAL SIGHT, and nothing here runs on a frame anybody sees.

     worldShade has already said how warm the SURFACE is, in c; what it
     cannot know is what kind of thing this is, and that is the whole of
     a thermal picture. A PERSON is warm whatever colour their coat is —
     the drawing's own light and dark only give the figure its shape,
     skin a shade over cloth — and a frozen one is the coldest thing in
     the picture, which is the extinguisher's joke played on the seeker
     (js/missiles.js will not lock a block of ice either). Somebody on
     fire is white. A vehicle is as warm as its engine says. Smoke is
     all but gone. The coals and the flames already added above stay
     added, because they are hot.
     ------------------------------------------------------------------ */
  if (thermal > 0.5) {
    float h = c.r;
    #ifdef INSTANCED_SPRITE
      if (warm > 0.5 && fullbright < 0.5) {
        float lum = dot(t.rgb, vec3(0.30, 0.59, 0.11));
        float body = mix(0.66, 0.86, lum);
        float at = clamp((vDepth - airNear) / max(1.0, airFar - airNear), 0.0, 1.0);
        h = mix(body, 0.06, at * at * 0.85);
      }
    #endif
    #ifdef FROST
      h = mix(h, 0.02, clamp(frost, 0.0, 1.0));
      h = max(h, max(alight, ash));
    #endif
    #ifdef INK
      /* the engine, with the paint giving the body its shape the way a
         person's drawing does */
      h = max(h, warmth * (0.64 + 0.14 * dot(t.rgb, vec3(0.30, 0.59, 0.11))));
    #endif
    h += dot(glowAdd, vec3(0.30, 0.59, 0.11));
    #ifdef SEE_THROUGH
      /* smoke, drawn over the scene rather than in it, which a thermal
         sensor sees straight through */
      gl_FragColor = vec4(vec3(h), t.a * 0.12);
    #else
      gl_FragColor = vec4(vec3(h), t.a);
    #endif
    return;
  }
  gl_FragColor = vec4(c + glowAdd, t.a);
}
`;

/** The shared uniform objects, for a shader that splices the GLSL above. */
export function worldUniforms() {
  return {
    globalLight:  world.globalLight,
    lightFalloff: world.lightFalloff,
    minLight:     world.minLight,
    fireLightPos:   world.fireLightPos,
    fireLightRange: world.fireLightRange,
    fireLight:      world.fireLight,
    fireLightColor: world.fireLightColor,
    /* AND THE LINE LIGHT. This list is a whitelist and not a spread, on
       purpose — a material takes exactly the uniforms it uses — which
       means a uniform added to `world` and to the GLSL and not to this
       is declared, sampled, and never bound: the branch reads zero and
       the feature is silently off. Six lines, and they are the six. */
    beamPos:        world.beamPos,
    beamDir:        world.beamDir,
    beamLen:        world.beamLen,
    beamRange:      world.beamRange,
    beam:           world.beam,
    beamSeed:       world.beamSeed,
    beamColor:      world.beamColor,
    airNear:      world.airNear,
    airFar:       world.airFar,
    skyTex:       world.skyTex,
    eyePos:       world.eyePos,
    skyLight:     world.skyLight,
    smokeColor:   world.smokeColor,
    smokeNear:    world.smokeNear,
    smokeFar:     world.smokeFar,
    smokeDensity: world.smokeDensity,
    tint:         world.tint,
    emberTime:    world.emberTime,
    emberRamp:    world.emberRamp,
    burnGrid:     world.burnGrid,
    burnOrigin:   world.burnOrigin,
    burnCell:     world.burnCell,
    burnCols:     world.burnCols,
    burnRows:     world.burnRows,
    /* and the thermal sight's switch — see world.thermal */
    thermal:      world.thermal,
    /* and a map's own light and fog — see world.lightColor */
    lightColor:   world.lightColor,
    ambientColor: world.ambientColor,
    fogAmbient:   world.fogAmbient,
    fogDefault:   world.fogDefault,
    airColor:     world.airColor,
    airOverride:  world.airOverride,
    /* and the sector grid, which vertex shaders read (SECTOR_GRID_GLSL) */
    sectorA:      world.sectorA,
    sectorB:      world.sectorB,
    sectorC:      world.sectorC,
    sectorRect:   world.sectorRect,
    sectorOn:     world.sectorOn,
    fogMarch:     world.fogMarch,
  };
}

function baseUniforms(texture, opts) {
  return {
    map:          { value: texture },
    alphaTest:    { value: opts.alphaTest ?? 0.0 },
    fullbright:   { value: opts.fullbright ? 1.0 : 0.0 },
    ...worldUniforms(),
  };
}

/* Level geometry: light is baked per vertex by the map builder, so an
   entire store's worth of walls sharing one texture is one draw call.
   `ink` adds the vehicles' second material to the same draw call, in the
   vertices — the walls never ask for it. */
export function createWallMaterial(texture, opts = {}) {
  const u = baseUniforms(texture, opts);
  /* a vehicle's engine, for the thermal sight — see `warmth` above */
  if (opts.ink) u.warmth = { value: 0.0 };
  return new THREE.ShaderMaterial({
    uniforms: u,
    defines: { PER_VERTEX_LIGHT: '', SURFACE_BURN: '', ...(opts.ink ? { INK: '' } : {}), ...(opts.tint ? { TINT: '' } : {}) },
    vertexShader: COMMON_VERT,
    fragmentShader: COMMON_FRAG,
    transparent: !!opts.transparent,
    side: opts.side ?? THREE.FrontSide,
    depthWrite: opts.depthWrite !== false,
    toneMapped: false,
    fog: false,
  });
}

/* Sprites: one light value for the whole quad, updated each tic from
   whichever sector the thing is standing in.

   `blend` is the one thing here that is not Doom. Doom had exactly one
   way of drawing a sprite — a cut-out, every pixel either there or not —
   and everything in this game that is a THING is drawn that way. Fire is
   not a thing. Two flames overlapping are brighter than one flame, which
   is the whole reason a fire reads as light rather than as orange
   wallpaper, and no amount of cut-out gets you there: it is the one
   effect that needs the frame buffer added to rather than replaced.

     'cutout' (the default)  alpha-tested, writes depth, Doom's way
     'add'                   added to what is there, no depth write
     'alpha'                 blended over it, no depth write — smoke */
export function createSpriteMaterial(texture, opts = {}) {
  const u = baseUniforms(texture, opts);
  u.light         = { value: opts.light ?? 1.0 };
  u.sky           = { value: opts.sky ?? 0.0 };
  u.billboardRot  = { value: 0.0 };
  u.spriteScale   = { value: new THREE.Vector2(opts.width ?? 64, opts.height ?? 64) };
  u.spriteOffset  = { value: new THREE.Vector2(0, 0) };
  /* every sprite can be frozen; the walls cannot, so only this one
     carries the uniform and the define that reads it */
  u.frost         = { value: 0.0 };
  u.ash           = { value: 0.0 };
  u.alight        = { value: 0.0 };
  const blend = opts.blend || 'cutout';
  /* Depth TESTING stays on for all three, always: a flame behind a
     gondola is behind the gondola. It is only depth WRITING that a
     translucent sprite must not do, or the next one to draw is clipped
     against a pane of glass the first one left behind. */
  return new THREE.ShaderMaterial({
    uniforms: u,
    /* an 'alpha' sprite is smoke, and smoke is the one thing the thermal
       sight looks through — see SEE_THROUGH */
    defines: { BILLBOARD: '', FROST: '', ...(blend === 'alpha' ? { SEE_THROUGH: '' } : {}) },
    vertexShader: COMMON_VERT,
    fragmentShader: COMMON_FRAG,
    transparent: blend !== 'cutout' ? true : !!opts.transparent,
    blending: blend === 'add' ? THREE.AdditiveBlending : THREE.NormalBlending,
    side: THREE.DoubleSide,
    depthWrite: blend === 'cutout' ? opts.depthWrite !== false : false,
    toneMapped: false,
    fog: false,
  });
}

/**
 * A CROWD OF THEM, in one draw call.
 *
 * The same shader as above with INSTANCED_SPRITE defined instead of
 * BILLBOARD, so the four things that were per sprite — where it is, how
 * big, how lit, and the four flags — arrive as instance attributes. One
 * of these per PICTURE rather than per person; js/standees.js owns them
 * and fills the buffers. Cut-out only, because that is what every thing
 * in the game is drawn as and because a cut-out needs no sorting.
 */
export function createStandeeMaterial(texture) {
  const u = baseUniforms(texture, { alphaTest: 0.5 });
  u.billboardRot = { value: 0.0 };
  /* `light`, `sky` and the flags are attributes now — but COMMON_VERT
     assigns the varyings from the uniforms before the instanced block
     overrides them, so they have to exist. */
  u.light = { value: 1.0 };
  u.sky = { value: 0.0 };
  u.charred = { value: 0.0 };
  /* whether this picture is a body, for the thermal sight — see `warm` */
  u.warm = { value: 0.0 };
  return new THREE.ShaderMaterial({
    uniforms: u,
    defines: { INSTANCED_SPRITE: '', FROST: '' },
    vertexShader: COMMON_VERT,
    fragmentShader: COMMON_FRAG,
    transparent: false,
    blending: THREE.NormalBlending,
    side: THREE.DoubleSide,
    depthWrite: true,
    toneMapped: false,
    fog: false,
  });
}

/* Flat, screen-space, no world lighting at all — the weapon in your hands
   and the status bar. Doom drew these straight into the frame buffer and
   so do we. */
export function createHudMaterial(texture) {
  const u = baseUniforms(texture, { alphaTest: 0.5, fullbright: true });
  u.light = { value: 1.0 };
  u.sky = { value: 0.0 };
  return new THREE.ShaderMaterial({
    uniforms: u,
    vertexShader: COMMON_VERT,
    fragmentShader: COMMON_FRAG,
    transparent: true,
    depthTest: false,
    depthWrite: false,
    toneMapped: false,
    fog: false,
  });
}
