/* =====================================================================
   MEWD — the sky
   =====================================================================

   A sky sector in this engine draws nothing and lets the background
   through, which is exactly what Doom did and is fine as long as the
   only thing outdoors is a courtyard. It stopped being fine when the
   store got a car park six thousand units across, and it stopped being
   a cylinder when the car park got a forest round it: a strip of
   painted cloud is a horizon, and a forest at night wants a whole sky —
   stars overhead, a glow where the town is, nothing at all where there
   is nothing.

   So the background is a SPHERE, wearing an equirect. It wore a
   photograph — a Polyhaven night, baked to the palette offline — and
   it wears a picture the page bakes now (js/skyart.js), for a given
   hour and weather, re-baked as the night goes. An equirectangular
   picture on a sphere needs no projection maths at all — the sphere's
   own u is longitude and its v is latitude, and turning your head does
   the right thing for free. Looking up shows sky rather than the top
   of a strip, which is the only thing the cylinder could never do.

   Three rules and it is convincing:

   IT IS AT INFINITY. Every frame it is moved to sit on the camera, so
   walking never gets you nearer to it. That is the whole trick — a sky
   you can approach is a wall with stars on it.

   IT IS NOT LIT, AND IT IS NOT IN THE AIR. Fullbright, no distance
   diminishing, drawn first with depth off so everything in the world
   lands in front of it whatever the far plane is doing. And the air —
   the fog every wall fades into — is not applied to it, which is a
   proof and not a preference: the air's colour IS the sky's horizon
   texel, so mixing the sky toward the air would be mixing it toward
   itself. What it DOES get is the smoke, at full distance, because a
   store throwing a column of smoke greys its own sky, and against a
   black night nobody could tell that it did not.
   And a map's FOG, which is not the air: the fog you are standing in,
   and any you look through, is over the sky too (see FOG_GLSL in
   js/material.js).

   IT IS SMALLER THAN THE FAR PLANE. Depth off does not switch off
   clipping, and the far plane now follows the weather in — 2600 units
   in mist — so the sphere is scaled each frame to sit inside it.
   ===================================================================== */

import * as THREE from 'three';
import { worldUniforms, WORLD_UNIFORMS_GLSL, FOG_GLSL } from './material.js';

const RADIUS = 4200;          // the sphere as built; scaled to fit the far plane

const VERT = /* glsl */`
varying vec2 vUv;
varying vec3 vDir;
void main() {
  vUv = uv;
  vDir = (modelMatrix * vec4(position, 1.0)).xyz - cameraPosition;
  gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
}
`;

const FRAG = /* glsl */`
uniform sampler2D map;
${WORLD_UNIFORMS_GLSL}
${FOG_GLSL}
varying vec2 vUv;
varying vec3 vDir;
void main() {
  vec3 c = texture2D(map, vUv).rgb;
  /* THE FOG YOU ARE IN, over the sky: at the user's request a fog fades
     into the sky, followed from the eye out to the far edge of the air
     through every sector on the way (FOG_GLSL) — so standing in a thick
     fog the sky is gone, and it comes back as you walk out. Only for a
     map with a fog; the game's own levels have none. */
  if (fogMarch > 0.5 || fogDefault.a > 0.0) {
    vec3 far = cameraPosition + normalize(vDir) * airFar;
    vec4 fa = fogAlong(cameraPosition, far, fogAirAt(far));
    c = c * fa.a + fa.rgb;
  }
  /* THROUGH THE THERMAL SIGHT the sky is the coldest thing there is —
     a clear night sky is, to a sensor, a hole into space — with the
     cloud a shade warmer than the gaps in it, and no smoke, which the
     sight sees through. See world.thermal in js/material.js. */
  if (thermal > 0.5) {
    gl_FragColor = vec4(vec3(0.015 + 0.05 * dot(c, vec3(0.30, 0.59, 0.11))), 1.0);
    return;
  }
  /* the same smoke a wall gets at the far end of its ramp, at the
     lowest light the wall's smoke can be lit to — see worldShade */
  c = mix(c, smokeColor * 0.7, smokeDensity);
  gl_FragColor = vec4(c, 1.0);
}
`;

/**
 * @param {THREE.Texture|HTMLImageElement} src  the sky as an equirect —
 *   the baker's texture, or an image if somebody hands one in
 */
export function buildSky(src) {
  let tex;
  if (src.isTexture) {
    tex = src;
  } else {
    /* an image from outside: nearest, no mips, the way the photograph
       was worn. Nothing loads one any more, and it costs six lines to
       keep the door open. */
    tex = new THREE.Texture(src);
    tex.magFilter = THREE.NearestFilter;
    tex.minFilter = THREE.NearestFilter;
    tex.generateMipmaps = false;
    tex.wrapS = THREE.RepeatWrapping;
    tex.wrapT = THREE.ClampToEdgeWrapping;
    tex.colorSpace = THREE.SRGBColorSpace;
    tex.needsUpdate = true;
  }

  /* The sphere's u runs the wrong way round when seen from inside —
     SphereGeometry is authored to be looked at from outside — so the
     picture is mirrored. A negative x scale on the mesh puts west back
     on the left. The bake is drawn for exactly this mapping (see the
     header of js/skyart.js), so the mirror is part of the contract and
     not a fix. */
  const g = new THREE.SphereGeometry(RADIUS, 48, 24);
  const mat = new THREE.ShaderMaterial({
    uniforms: { map: { value: tex }, ...worldUniforms() },
    vertexShader: VERT, fragmentShader: FRAG,
    side: THREE.BackSide, depthWrite: false, depthTest: false, fog: false, toneMapped: false,
  });
  const mesh = new THREE.Mesh(g, mat);
  mesh.scale.set(-1, 1, 1);
  mesh.frustumCulled = false;
  mesh.renderOrder = -1000;
  mesh.name = 'sky';
  return mesh;
}

/** Park it on the camera, so it can never be walked towards, and keep
 *  it inside the far plane. The eye is the horizon: the sphere's
 *  equator sits at the camera's own height, which is where the horizon
 *  of a flat world is. */
export function followSky(mesh, camera) {
  mesh.position.copy(camera.position);
  const far = camera.far || RADIUS * 2;
  const s = Math.min(1, (far * 0.9) / RADIUS);
  mesh.scale.set(-s, s, s);
}
