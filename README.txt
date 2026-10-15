MEWD — A TERRAIN ENGINE
=======================

MEWD draws places: real ones, cut out of the world as a square and made
out of open map data (heights, water, land cover, OpenStreetMap), and
golf's procedural island. Each is a scene of the chunked island system
(godot/island/): terrain meshed in chunks at five levels of detail and
streamed round the eye, pre-baked so it loads at once, with high-
resolution PBR ground, billboard plants rendered from CC0 3D models, real
water, a physical sky with raymarched clouds and weather, the sun and the
moon where they really are, and a camera to fly round it. Nothing else:
the game it used to be (MEWD, Made Entirely Without Doom) is gone, at the
user's request ("i just wanted the terrain engine, you can strip all
gameplay elements"), and lives in the git history.

It is built for ANDROID (arm64) and LINUX x86_64, on Godot 4.7's Mobile
renderer.

  godot/            the engine: Godot 4.7, GDScript
  godot/island/     the island system (from golf), the real places, the sky
  tools/            making a place (earth_fetch.py), its look
                    (earth_pack.py), baking (bake_island.gd), the builds


GET IT
------

  https://github.com/verdictzero/mewd-engine/releases/tag/android
  https://github.com/verdictzero/mewd-engine/releases/tag/linux

Both are rebuilt on every push to main.


RUN IT
------

Godot 4.7. The project is the repository root. Once, and again whenever a
place or its code changes, bake the places (the builds do it themselves):

    godot --headless --editor --quit
    godot --headless --script res://tools/bake_island.gd -- --all --if-missing

Then `godot --path .` (or F5 in the editor). After `--`:

    --map=KEY              the place: earth_oeschinen (the first), island0
    --at=X,Z --high=M      where the eye starts: metres east and south of
                           the middle, and over the ground
    --y=Y                  or at a height in the world (under a lake, say)
    --face=X,Z | --turn=DEG | --look=sun|moon [--look-off=DEG,DEG]
    --pitch=DEG            looking up (+) or down
    --walk                 on the ground, not flying
    --retro                the old picture: 360 rows of chunky pixels,
                           dithered
    --sky-hour=H --sky-day=D --sky-weather=NAME --sky-minutes=M
                           the clock, the day of the year, the weather
                           (clear, fair, partly_cloudy, cloudy, overcast,
                           foggy, light_rain, rain, storm, light_snow,
                           snow), a day in M real minutes
    --cine=NAME:VALUE,... | --cine=off
                           the cinema pass's numbers, or none
    --shot=out.png [--frames=N]
                           a picture once the place is up, then quit


CONTROLS
--------

  mouse          click to look (Esc lets the mouse go)
  W A S D        fly (and the arrow keys)     E / Q   up / down
  Shift / Ctrl   four times as fast / a quarter     wheel  flying speed
  G              walk on the ground or fly
  [ ]            the hour back or on (Shift: by the hour)
  T              run the clock or hold it      F   the next weather
  K              the cinema on or off          P   native or retro picture
  N              the next place                I   the words on or off
  F12            a picture to user://          H   these keys
  pad            left stick flies, right looks, triggers climb, A walks
  touch          one finger looks, two move (and spread or pinch to climb)


A REAL PLACE
------------

tools/earth_fetch.py takes a latitude, a longitude and a size and makes a
square of the real world an island, out of open data fetched over HTTPS
with no key: the AWS Terrain Tiles (or Copernicus GLO-30) for the height,
ESA WorldCover for what is on the ground, OpenStreetMap through Overpass
for the water, the roads, the rock and scree and the woods' leaf type:

    python3 tools/earth_fetch.py NAME --lat .. --lon .. --size METRES \
        --title "TITLE" --register
    godot --headless --editor --quit
    godot --headless --script res://tools/bake_island.gd -- --map=earth_NAME

It writes godot/island/earth/NAME/ (the grids and region.json), the
place's field and scene and its entry in godot/scripts/level/islands.gd.
EarthField answers the island system out of the grids, so the chunks,
LODs, bakes and plants are the island system's own.

THE LOOK:
  THE GROUND  twelve CC0 photo-scanned PBR materials at 2048 px (colour,
    height, normal, roughness, occlusion), height-blended off the data and
    projected triplanar, so a cliff is rock square-on, with the beds and
    water streaks of a limestone wall; its mountains' shadows and its
    clouds' shadows across it; caustics on the bed under the water.
  THE WATER   double-sided: from above, the bed through it bent by the
    waves and taken by the depth, the cliffs mirrored in it (screen-space
    reflections), the sun's glint, foam on the shore; from below, Snell's
    window onto the world above and the water's own colour round it, and
    everything under the surface fogged.
  THE PLANTS  billboards rendered from CC0 models at up to 1024 px, lit
    by the place's ambient light alone and a light baked into each one
    where it stands (under a canopy, on a slope); they cast no shadows.
    The grass is as thick as it goes round the eye.
  THE SKY     EnviroSky, after Unity's Enviro: the air's scattering,
    raymarched cumulus and cirrus on the wind, the sun and the moon where
    they are over the place at its hour and date, stars, eleven weathers
    with rain, snow and lightning.
  THE CINEMA  god rays past the ridges and through the clouds, the sun's
    lens flare (a starburst, the blue anamorphic streak, a halo, the
    iris's ghosts), bloom, the haze glowing gold into the light, and a
    colour grade (a film's shoulder, teal shadows and amber highlights, a
    vignette, grain).

OESCHINENSEE is the first: 3 km of the Bernese Oberland round the lake
under the Bluemlisalp, on a July evening.

The PBR textures and the plant sprites are the earth pack, shared by every
place (tools/earth_pack.py: textures, models, billboards, meadow).


THE REPOSITORY
--------------

  godot/scenes/main.tscn, godot/scripts/main.gd   the viewer: a place,
                         the camera, the keys, --shot
  godot/scripts/viewer/  the camera (fly_camera.gd), the words (hud.gd)
  godot/scripts/render/lofi.gd, godot/shaders/lofi.gdshader
                         the picture: the grade, grain, the retro pixels
  godot/scripts/level/islands.gd   the places
  godot/island/scripts/world/      the island system: the field
                         (SCRIPT_island_field.gd, SCRIPT_earth_field.gd),
                         the mesher, the world's streaming, the plants,
                         the bakes, the water (SCRIPT_earth_dress.gd), the
                         sun's shadows (SCRIPT_earth_sun.gd), the cinema
                         (SCRIPT_cinema_post.gd)
  godot/island/scripts/SCRIPT_enviro_sky.gd   the sky, the clock, the
                         weather
  godot/island/shaders/  every surface's shader
  godot/island/earth/    the real places and the earth pack
  godot/tests/           the headless suites (tools/godot-test.sh)
  tools/                 earth_fetch.py, earth_pack.py, earth_billboards.gd,
                         earth/ (the scene and the sky's noise),
                         bake_island.gd, the builds

GODOT.txt is the changelog: what each change did and why.


CREDITS AND LICENCES
--------------------

The island system and golf's island, its ground and plant textures, come
from golf (the user's own). The real places' ground textures are Poly
Haven's and ambientCG's, CC0, and their plants are rendered from Poly
Haven's CC0 models (godot/island/earth/textures/layers.json and
sprites/sprites.json say which). OESCHINENSEE's data: heights from the
Mapzen Terrain Tiles on AWS (SRTM and others); land cover © ESA
WorldCover project 2021 / contains modified Copernicus Sentinel data
(2021) processed by the ESA WorldCover consortium, CC BY 4.0; map data ©
OpenStreetMap contributors, ODbL. Each region's region.json carries its
own attribution. DejaVu (the words) is under its own licence
(assets/fonts/dejavu/LICENSE.txt). Godot is MIT.
