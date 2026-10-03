MEWD
====

MEWD stands for MADE ENTIRELY WITHOUT DOOM. It was a Doom-style engine
built from scratch; at the user's request it is now a game on
procedurally generated islands (golf's island system, pre-baked), with
the player, the crowd and the guns kept.

The game: you are dropped on an island with a few hundred people
wandering its hills and woods. You burn, freeze, bore, shred, lance,
rocket, electrocute or potato whatever is in front of you, and the
picture is chunky pixels snapped to an earth-tone palette the whole
time. The trees, bushes, ferns and grass are cover for the eye only:
nothing in the vegetation stops a body or a round.

It is built for two targets only: ANDROID (arm64, an Anbernic RG557 or
a phone) and LINUX x86_64. There is no web build.

  godot/            the game: Godot 4.7, GDScript
  godot/island/     the island system, from golf

(The original JavaScript build the Godot one was ported from has been
deleted; it is in the git history before the island.)


GET IT
------

  https://github.com/verdictzero/mewd-engine/releases/tag/android
                                                        the Android APK
  https://github.com/verdictzero/mewd-engine/releases/tag/linux
                                                        Linux x86_64 (Ubuntu)

Both are rebuilt on every push to main or claude/godot-rewrite. NEW
GAME on the title lists the islands.


RUN IT LOCALLY
--------------

Godot 4.7 (the standard editor binary). The project is the repository
root. Once, and again whenever an island or its code changes, bake the
islands (a couple of minutes; the builds do this themselves):

    godot --headless --editor --quit
    godot --headless --script res://tools/bake_island.gd -- --all --if-missing

Then:

    godot                        # opens the editor; F5 runs the game
    godot --path . -- --play     # straight into the game

Arguments after `--`:

    --play                skip the title
    --map=NAME            which island (island0)
    --seed=N              where the crowd is dropped
    --weapon=NAME         start holding FLAMER, EXTINGUISHER, BORE,
                          MINIGUN, LANCE, LAUNCHER, ARC or POTATO
    --at=X,Y,DEG          start somewhere else
    --terminal            the terminal first
    --touch               the phone's controls, without a touch screen
    --pause               open the pause menu
    --prof                print where each frame's time goes
    --shot=out.png        render --shot-frames=N frames, save, quit
    --server[=PORT]       host a match (see NETWORK PLAY)
    --join=HOST[:PORT]    join one; --name=NAME

The Android APK is `sh tools/build-android.sh`, with the Android
templates, the SDK's build tools and Java; see GODOT.txt. The Linux
build is `sh tools/build-linux.sh`: one x86_64 file with the game
packed inside, needs Vulkan, runs on Ubuntu 20.04 or later (chmod +x
mewd.x86_64 and run it). Both fetch their templates and bake the
islands if they need to.


CONTROLS
--------

KEYBOARD AND MOUSE

    WASD / arrows   move (Q, E strafe)      mouse           look
    Shift           run                     Space           jump
    F               use                     Ctrl / left     fire
    Z, C / right    scope up, step its zoom (lance, launcher, potato)
    1-8 / wheel     weapons                 Esc / P         pause
    Tab             match score

Click the picture to capture the mouse; Esc gives it back.

PAD. Any pad on any port: a handheld's built-in controller (the
Anbernic RG557 and its kind), a USB or Bluetooth controller, or both at
once. Every binding answers to every device. In a browser, a pad the
engine has no mapping for is given the standard layout when it
connects. On Android each pad's mapping is taken off as it connects:
Godot already reports the buttons in order there, and its fallback
layout threw away the L2 and R2 buttons (an RG557's triggers). The
triggers fire and jump on whichever form they arrive in: buttons 16
and 15, or axes 5 and 4, or the mirrored axes 6 and 7.

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

THE ISLANDS (godot/scripts/level/islands.gd). Every level is one of
golf's procedural islands, generated ahead of time and baked into the
build; NEW GAME lists them.

    ISLAND 0     golf's island_0 without its golf, ruins or crash site:
                 2.5 km of hills, firs, bushes, ferns and grass, a cliff
                 all round dropping into a sea of cloud, and 360 people
                 dropped on it with you (--seed=N moves them)

THE VEGETATION IS VISUAL COVER, and stays that way: you, the crowd and
every round go through trees, bushes, ferns and grass. A tree you walk
into dissolves as you reach it. What stops a body is the ground: a crag
too steep to step up, or the cliff at the coast.

THE WEAPONS, in slots 1 to 8:

    1  FLAMER               a stream that lights people and cars
    2  EXTINGUISHER         freezes them solid; a frozen one shatters
    3  CEREBRAL BORE        a seeker that drills in and holds; blood
                            pours out the whole time, then the head
                            goes, absurdly: the body torn apart twice
                            over, brains, eyes and teeth flung up, a
                            spray like a burst main, pools, and the neck
                            pumping for three seconds after. Every part
                            that lands lies about for a minute (meat, a
                            hand, a foot, an eye, guts, ribs, a heart, a
                            brain), and one in three of a rocket's do too
    4  MINIGUN              spins up, eats a belt, leaves holes
    5  POSITRON LANCE       a charged column with a scope; sears walls
    6  QUAD LAUNCHER        four heat-seeking rockets, a thermal sight
    7  ARC MAW              a charge, then lightning that chains; while
                            it charges a ball of blue energy grows in
                            the maw with motes streaming into it
    8  IRISH POTATO CANNON  a bouncing potato with a rainbow trail and
                            a colour-cycling nuke at the end of it
                            (OFF FOR NOW: not in the loadout, slot 8
                            picks nothing; player.gd `owned`)

WHAT THE BIG GUNS LEAVE (godot/shaders/blast_decal.gdshader):
  - A rocket leaves a pitted crater. Its rim glows molten and cools,
    and a shockwave ring races out from it in the first half second.
    Long soot rays spread out from the crater, the shrapnel pocks are
    hot for a few seconds, and embers stay in the cracks for a while.
    Soot is thrown up every wall near the blast.
  - A potato leaves a crater of fused rainbow glass. Its colours cycle
    for as long as it is there, it glints, and rainbow petals and a
    white flash ring spread round it.
  - The arc maw burns Lichtenberg figures, the branching scars real
    lightning leaves. One goes under everybody a bolt goes through,
    smaller ones under those its field catches, and one where a branch
    earths itself or a bolt hits a wall. They crackle blue-white, then
    fade to char with a ghost of blue in it.

Every gun is loaded when a level is built, and the loading screen's
warm-up draws them all once, along with every other effect the level
has built (rockets, sparks, the scopes' feeds), so the first swap or the
first shot never stops to compile a shader. There are no street lamps
in the Godot build any more; a lamp in an older map is left out when
it is built.

The minigun is the network loadout. The pause menu's DEBUG page has
INFINITE AMMO and INVINCIBLE, both on by default.

THE PEOPLE. Shoppers and townies watch, flee and panic contagiously;
they burn, freeze, thaw and come apart. The police and the army (the
responders) are off for now. A rocket takes people apart; every impact
is a mark on the ground. The dead do not stay: a shopper goes at once,
and the blood is what is left.

THE RENDERER is Mobile on Vulkan, on Android and on Linux. On the
island the marks are quads laid on the ground.

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

LAN play, a Godot host and Godot clients:

    godot --headless --path . -- --server[=PORT] [--map=island0]
          [--seed=N] [--max=16] [--frags=N]
    godot --path . -- --join=HOST[:PORT] [--name=NAME]

Or JOIN host:port at the terminal. Deathmatch on an island: first to
20, two-second respawns, spawn guard, infinite ammo. The simulation is
35 tics a second; a client predicts and reconciles, the host rewinds
to where you saw the others when it judges a shot. TAB shows the table.
Every machine has the island baked; the host draws none of it.


THE REPOSITORY
--------------

    project.godot, export_presets.cfg   the Godot project (the root)
    godot/scenes/main.tscn              the one scene
    godot/scripts/main.gd               boot, title, game, pause
    godot/scripts/pad.gd                the pad: any device, the menus
    godot/scripts/core/                 U: maths, fonts, helpers
    godot/scripts/level/                the Level, and the island as one:
                                        its ground, collision, sight
    godot/island/                       golf's island system: field,
                                        mesher, world, bakes, plants, sky
    godot/scripts/game/                 the simulation: actors, states,
                                        weapons, effects, vehicles,
                                        weather
    godot/scripts/render/               the picture: lofi, standees,
                                        decals, particles, tracers,
                                        the gun, scopes, HUD
    godot/scripts/net/                  the wire, host, client, match
    godot/scripts/title/, ui/           title, pause, terminal, touch
    godot/scripts/audio/                sound and music
    godot/shaders/                      the shaders
    godot/data/                         palette, LUT, texture list
    godot/tests/                        the headless suites
    assets/                             the game's art: people, models,
                                        textures, skies, fonts, music,
                                        sfx, logo
    tools/                              build, bake and test scripts
    GODOT.txt                           the Godot build in detail
    HISTORY.txt                         the old README: the design diary
                                        of the JavaScript build, kept
    TOWN.txt, SIGHT.txt                 design notes for the town and
                                        for fog, sky and occlusion



TOOLS
-----

    tools/godot-test.sh        the test suites
    tools/bake_island.gd       bake the islands (terrain, plants, ground)
    tools/build-android.sh     export the Android APK
    tools/ci-android.sh        the same on a clean machine (the android
                               workflow, which puts it up as a release)
    tools/build-linux.sh       export the Linux x86_64 build (the linux
                               workflow puts it up as a release)
    tools/make-icons.py        every icon from the MEWD logo
    tools/prep-*.mjs, .py      crunch outside art into assets/ (people,
                               troops, models)


TESTS
-----

    sh tools/godot-test.sh

runs every headless suite in turn (bake the islands first) and exits
non-zero if any fails:

    weapons    every gun against real people on the island
    island     the ground off the bake, you and the crowd on it, the
               coast, the hills, rounds and blasts into the ground
    net        the wire's bytes, a match over loopback, a real socket
               host with two clients
    death      the dead removed, and their sprites with them
    pad        the pad's bindings on every device, the menus' reading,
               a map set up by hand, the SET UP PAD wizard driven

With xvfb, `--shot=out.png` renders a picture of anything for checking
by eye; godot/tests/island_shot.gd pictures a gun held on a crowd.


RELEASES
--------

.github/workflows/android.yml and linux.yml build on every push to main
or claude/godot-rewrite, bake the islands (kept between runs in the
Actions cache), and replace the rolling releases "android" and "linux".


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
GODOT.txt.
