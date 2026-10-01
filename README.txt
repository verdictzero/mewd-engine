MEWD
====

MEWD stands for MADE ENTIRELY WITHOUT DOOM: a Doom-style engine built
from scratch, with none of Doom's code or data in it. The engine is
MEWD, the game is MEWD Demo, and the map editor is MEWD Editor.

The game: it is two in the morning, you have a flamethrower, and there
is a hedge maze with five hundred people wandering it. Or a strip mall
with a supermarket in the middle. Or a two-team maze with a fort at
each end. You burn, freeze, bore, shred, lance, rocket, electrocute or
potato whatever is in front of you, the SWAT arrive in vans, then the
army in hover APCs, and the picture is 320 rows of chunky pixels
snapped to an earth-tone palette the whole time.

Two builds live in this repository:

  the Godot build   godot/ — Godot 4.3, GDScript. This is the game,
                    the editor and the site. Everything below is about
                    it unless it says otherwise.
  the classic build js/ — the original, in JavaScript on three.js, no
                    build step. It is the reference the Godot build was
                    ported from, still runs, and is published under
                    classic/ on the site.


PLAY IT
-------

  https://verdictzero.github.io/mewd-engine/            the Godot build
  https://verdictzero.github.io/mewd-engine/classic/    the classic build
  https://github.com/verdictzero/mewd-engine/releases/tag/android
                                                        the Android APK
  https://github.com/verdictzero/mewd-engine/releases/tag/linux
                                                        Linux x86_64 (Ubuntu)

The site opens on the MEWD title. NEW GAME is a fresh maze; MAP EDITOR
is the editor; DOWNLOAD ZIP is the repository. The classic build opens
on a terminal instead (black glass, a prompt reading INTERFACE 2037);
type G or GAME for the game, JESSE for the two-team maze, E or EDIT for
the editor, JOIN [host:port] to join a match, QUIT to leave. The
classic build also takes ?seed=N, ?sprawl, ?jesse, ?grid, ?edit,
?play and ?join=host:port on the URL.

The site is built for WebGL 2 with no threads (GitHub Pages cannot
send the headers a browser wants before it lends a page threads), so
it runs on a phone, a handheld's browser or a desktop alike. A pad
plugged in or built in is recognised on its first press.


RUN IT LOCALLY
--------------

THE GODOT BUILD needs Godot 4.3 (the standard editor binary). The
project is the repository root:

    godot                        # opens the editor; F5 runs the game
    godot --path . -- --play     # straight into the game

A fresh clone should be imported once before a headless run:
`godot --headless --import`. Arguments after `--`:

    --play                skip the title
    --map=NAME            maze (default), jesse, sprawl, grid, layers
    --seed=N              the maze for seed N
    --weapon=NAME         start holding FLAMER, EXTINGUISHER, BORE,
                          MINIGUN, LANCE, LAUNCHER, ARC or POTATO
    --at=X,Y,DEG[,LAYER]  start somewhere else
    --edit                straight into MEWD Editor
    --terminal            the classic build's terminal first
    --touch               the phone's controls, without a touch screen
    --pause               open the pause menu
    --prof                print where each frame's time goes
    --shot=out.png        render --shot-frames=N frames, save, quit
    --server[=PORT]       host a match (see NETWORK PLAY)
    --join=HOST[:PORT]    join one; --name=NAME

The web export is `sh tools/build-web.sh [outdir]`, with Godot's web
export template installed. The Android APK (arm64, for a handheld like
the Anbernic RG557 or a phone) is `sh tools/build-android.sh`, with the
Android templates, the SDK's build tools and Java; see GODOT.txt. The
Linux build is `sh tools/build-linux.sh`. It is one x86_64 file with
the game packed inside, needs Vulkan, and runs on Ubuntu 20.04 or
later: chmod +x mewd.x86_64 and run it. The script fetches its
templates itself.

THE CLASSIC BUILD has no install and no build step: open index.html,
or serve the folder (`node tools/server.mjs` serves it and hosts a
match on port 7777).


CONTROLS
--------

KEYBOARD AND MOUSE

    WASD / arrows   move (Q, E strafe)      mouse           look
    Shift           run                     Space           jump
    F               use (doors)             Ctrl / left     fire
    Z, C / right    scope up, step its zoom (lance, launcher, potato)
    1-8 / wheel     weapons                 Esc / P         pause
    F2              the map editor          Tab             match score
    F5              (editor) play the map

Click the picture to capture the mouse; Esc gives it back.

PAD. Any pad on any port: a handheld's built-in controller (the
Anbernic RG557 and its kind), a USB or Bluetooth controller, or both at
once. Every binding answers to every device. In a browser, a pad the
engine has no mapping for is given the standard layout when it
connects. On Android the system already reports the buttons in order,
so nothing is remapped.

    left stick / D-pad   move               right stick     look
    R2                   fire               L2 / X          jump
    A                    use                B               scope, zoom
    L1 / R1              previous / next weapon (Y: next)
    L3 / R3              run                Start / Select  pause

In the menus the D-pad or either stick moves, A takes, B goes back,
and L1/R1 turn the pause menu's pages; at the terminal A is Enter and
B is Backspace. In a browser the game learns of a pad on its first
press, so press something. Android's Back button (often a handheld's
Select) pauses the game; it never quits.

SET UP PAD, on the title or in the pause menu's footer, is a guided
wizard for a pad whose buttons land wrong. It asks for each action in
turn (move, look, fire, jump, use, scope, the guns, run, pause), and
keeps whatever the pad sends: a button, a stick or a trigger, or a
key. Waiting 10 seconds or pressing SKIP leaves a step as it was.
DEFAULTS puts the standard layout back. The menus follow the new map
too, so the button that is USE is also OK. Along the bottom the wizard
shows what the pad is sending, raw, which helps tell what a strange
pad is doing. The map is kept in user://pad_map.cfg.

TOUCH (a phone, or a handheld's glass). A stick appears where the left
thumb lands; the rest of the glass is look. FIRE, JUMP, USE and SWAP
sit under the right thumb, AIM and ZOOM further out when the gun has a
sight, PAUSE in the corner. A pad in use takes the thumb controls off the picture; a finger brings
them back. A phone held upright is told to ROTATE.


THE GAME
--------

THE MAPS (godot/scripts/maps/). Each is generated as an editor
document and compiled by the same compiler the editor uses.

    THE MAZE     the default: an 18x18 braided hedge maze with plazas,
                 different every game (--seed=N repeats one), five
                 hundred people in it
    JESSE        two fortified bases joined by a multi-zone maze, a new
                 one every time; team deathmatch on a network
    THE SPRAWL   the strip mall, its car park and the wood: SellWrong,
                 the supermarket, and its neighbours
    THE GRID     a walled square with two hundred shoppers, for tests
                 and pictures
    THE ANNEXE   a yard, a shop with an office over it and a terrace:
                 the room-over-room map, in two layers

THE WEAPONS, in slots 1 to 8:

    1  FLAMER               a stream that lights people and cars
    2  EXTINGUISHER         freezes them solid; a frozen one shatters
    3  CEREBRAL BORE        a seeker that drills in and holds
    4  MINIGUN              spins up, eats a belt, leaves holes
    5  POSITRON LANCE       a charged column with a scope; sears walls
    6  QUAD LAUNCHER        four heat-seeking rockets, a thermal sight
    7  ARC MAW              a charge, then lightning that chains; while
                            it charges a ball of blue energy grows in
                            the maw with motes streaming into it
    8  IRISH POTATO CANNON  a bouncing potato with a rainbow trail and
                            a colour-cycling nuke at the end of it

Every gun is loaded when a level is built, and the loading screen's
warm-up draws them all once, along with every other effect the level
has built (rockets, sparks, the scopes' feeds), so the first swap or the
first shot never stops to compile a shader. There are no street lamps
in the Godot build any more; a lamp in an older map is left out when
it is built.

The minigun is the network loadout. The pause menu's DEBUG page has
INFINITE AMMO and INVINCIBLE, both on by default.

THE PEOPLE. Shoppers watch, flee and panic contagiously; they burn,
freeze, thaw and come apart. The SWAT arrive in vans and chase with
Doom's chase, then the army in hover APCs; on a map with stairs and
doors they find the way (A* over the level's rooms). A rocket takes
people apart; blood goes up the walls; every impact is a decal. The
dead do not stay: a shopper goes at once, a trooper after two seconds
on the floor, and the blood is what is left.

THE RENDERER is Mobile on the desktop and on Android, for real decals:
blood that wraps a corner, pools that run over a step, scorches and the
lance's sears painted across whatever they land on. The web is always
Compatibility, and there the marks are the flat quads they were. Both
draw the same picture otherwise. Bullet holes are quads everywhere.

THE PICTURE. The world is drawn at the chunky grid's own size (320
rows of 2:3 pixels by default), Bayer-dithered one step and snapped to
an earth palette, then blown up nearest-neighbour, so a 4K window costs
what a small one does. Every surface is unlit and lit by its own
shader: depth diminishing, the sky's lift, Doom's 32 light steps, then
the air. The gun is drawn in a world of its own over the room.

THE PAUSE MENU keeps its settings in user://prefs.cfg:

    CONTROLS   look speed, invert look, music
    PICTURE    render size, pixel rows, pixel aspect, palette snap
    LEVELS     brightness, contrast, gamma
    WORLD      time of night (22:00 to 08:00), weather
    DEBUG      infinite ammo, invincible, and the performance overlay
               (frame rate and time, draw calls, where the time goes,
               and the device's renderer, GPU, CPU and OS), on by default


NETWORK PLAY
------------

LAN play, on the same wire as the classic build, so either kind of
client joins either kind of host:

    godot --headless --path . -- --server[=PORT] [--map=jesse|maze]
          [--seed=N] [--max=16] [--frags=N]
    godot --path . -- --join=HOST[:PORT] [--name=NAME]
    node tools/server.mjs --map maze --port 7777     the classic host
    https://…/classic/?join=HOST:PORT                a page joining

Or JOIN host:port at the terminal. JESSE is team deathmatch (SWAT
black against army green), THE MAZE deathmatch. First to 40 (team) or
20, two-second respawns, spawn guard, infinite ammo. The simulation is
35 tics a second; a client predicts and reconciles, the host rewinds
to where you saw the others when it judges a shot. TAB shows the table.
Hosting needs a machine; a browser page can only join.


THE MAP EDITOR
--------------

MEWD Editor is in the game: MAP EDITOR on the title, F2 from the game,
`-- --edit`, or E at the terminal. It is in the mould of SLADE and
Ultimate Doom Builder: a plan view and a 3D view (Tab swaps which is
big; Split, 2D, 3D layouts), modes for vertices, lines, sectors,
things, props, drawing, shapes, scatter and doors, an inspector, a
texture browser and texture editor, a things tab, a step generator,
scatters of plants and people, room styles, layers for room over room,
undo and redo, copy and paste, snap, and Q for visual mode. PLAY (F5)
hands the document to the game and starts you where the 3D camera
stands; F2 comes back. Help in the menu lists the keys.

The LAYERS tab is a layers panel in the style of Photoshop. The
storeys are a stack, with the top one first, and each has a
thumbnail of its plan, a name and an eye.
  - Click a storey to edit it.
  - The eye hides a storey from the plan and the 3D view; the map
    still keeps it. Alt+click the eye to show that storey alone.
  - Double-click to rename a storey.
  - Drag a storey up or down the stack. It trades heights with the
    storeys it passes.
  - Right-click, or use the buttons along the bottom, to add,
    duplicate, move or delete a storey.
  - Open a storey to see its hierarchy. Each room sits under the room
    it is cut from, and each thing under the room it stands in. Click
    one to select it, or double-click to frame it.

Files are JSON (.gssmap.json) and open in either build's editor.
Ctrl+S saves into user://mewd-editor/maps/; File > Open… and Save as
file… use the desktop's file dialog; an autosave is opened on start.
File > Open demo gives a new MAZE, THE SPRAWL, a new JESSE, THE GRID
or THE ANNEXE.


THE REPOSITORY
--------------

    project.godot, export_presets.cfg   the Godot project (the root)
    godot/scenes/main.tscn              the one scene
    godot/scripts/main.gd               boot, title, game, pause, editor
    godot/scripts/pad.gd                the pad: any device, the menus
    godot/scripts/core/                 U: maths, fonts, helpers
    godot/scripts/level/                document -> Level: the compiler,
                                        geometry, collision, textures
    godot/scripts/maps/                 the map generators
    godot/scripts/game/                 the simulation: actors, states,
                                        weapons, effects, vehicles,
                                        doors, nav, weather
    godot/scripts/render/               the picture: lofi, standees,
                                        decals, particles, tracers,
                                        the gun, scopes, HUD
    godot/scripts/net/                  the wire, host, client, match
    godot/scripts/editor/               MEWD Editor
    godot/scripts/title/, ui/           title, pause, terminal, touch
    godot/scripts/audio/                sound and music
    godot/shaders/                      the shaders
    godot/data/                         palette, LUT, texture list
    godot/tests/                        the headless suites
    assets/                             art both builds load: people,
                                        forest, models, textures, skies,
                                        fonts, music, sfx, logo
    js/, index.html, css/, vendor/      the classic build
    art/                                source art baked into the
                                        classic build
    tools/                              build, bake and test scripts
    GODOT.txt                           the Godot build in detail:
                                        every system and where each
                                        piece of the classic build went
    HISTORY.txt                         the previous README: the whole
                                        design diary of the classic
                                        build, kept as it was
    TOWN.txt, SIGHT.txt                 design notes for the town and
                                        for fog, sky and occlusion

The classic build's folders carry a .gdignore, so Godot sees assets/
and godot/ and nothing else.


TOOLS
-----

    tools/godot-test.sh        the Godot build's test suites
    tools/build-web.sh         export the Godot build for the web
    tools/build-android.sh     export the Android APK
    tools/build-linux.sh       export the Linux x86_64 build (the linux
                               workflow puts it up as a release)
    tools/ci-android.sh        the same on a clean machine (the android
                               workflow, which puts it up as a release)
    tools/build-site.sh        assemble the classic build into public/
    tools/godot-data.mjs       write godot/data/ from the classic
                               build's tables (palette, LUT, textures)
    tools/build-texpack.py     the texture pack from assets/textures
    tools/server.mjs           the classic dedicated server
    tools/smoke-test.mjs       the classic build's checks, no browser
    tools/bake-*.mjs           art/ into source: logo, plants, sky,
                               icons, models
    tools/prep-*.mjs, .py, .sh crunch outside art into assets/


TESTS
-----

    sh tools/godot-test.sh

runs every headless suite in turn and exits non-zero if any fails:

    weapons    every gun against real people in the maze
    forest     the wood's collision and scatter
    jesse      the JESSE generator against the classic build, 48 seeds
    sprawl     THE SPRAWL and THE GRID against the classic build's counts
    net        the wire's bytes, a match over loopback, a real socket
               host with two clients
    editor     the editor's edits and files against the classic editor
    editorui   the editor driven by input events, into the game and back
    decals     real decals: the tiles, eight a mesh, the rest quads
    death      the dead removed, and their sprites with them
    pad        the pad's bindings on every device, the menus' reading,
               a map set up by hand, the SET UP PAD wizard driven
    layers     room over room on THE ANNEXE
    layerspane the editor's layers panel: the stack, the hierarchy, the
               eye, moving, duplicating and deleting storeys

The classic build's test is `node tools/smoke-test.mjs`. With xvfb,
`--shot=out.png` renders a picture of anything for checking by eye.


DEPLOYING
---------

.github/workflows/pages.yml runs the classic build's smoke test, then
on main fetches Godot 4.3 and its web template, exports the Godot
build to the root of the site, assembles the classic build under
classic/, and publishes to GitHub Pages. The repository's Pages source
must be GitHub Actions. .gitlab-ci.yml does the same for GitLab.


CREDITS AND LICENCES
--------------------

The logo, the SWAT and army sheets, the minigun, the vans, the APC,
the potato cannon, the ground and plant textures (github.com/
verdictzero/vandre) and the crowd's drawings (github.com/verdictzero/
galvarius) are the user's own. The fire extinguisher rifle and the
cerebral bore are Vaportrash's, off Sketchfab, CC-BY-4.0; the
flamethrower is Vaportrash's too and carries no licence. Michroma
(the title face) is SIL OFL. three.js r160 is MIT. Godot is MIT. The
night-sky photograph in assets/sky is Polyhaven's, CC0, and no longer
shipped.


WHAT IS NOT DONE
----------------

  the fire that spread — fuel grid, haze, the wood catching, the
    brigade — was taken out of the Godot build at the user's request;
    people and cars still burn
  the town, the gunship, breaches and ruins are the classic build's
    and are not being ported
  no save, no second level, no level flow; CONTINUE and LOAD GAME on
    the title shake their heads
  only the SWAT and the army fight back
  a match shares the players and nothing else: crates and cars are
    each machine's own
  a real decal is lit by the light where it is, not per pixel, and the
    thermal sight does not see them; past eight on one tile's mesh the
    rest are flat quads
  the pad's standard-layout fallback (in a browser) is a guess for a
    controller the engine does not know; SET UP PAD fixes a strange one

Everything else the Godot build leaves out is listed at the end of
GODOT.txt. The classic build's own list is at the end of HISTORY.txt.
