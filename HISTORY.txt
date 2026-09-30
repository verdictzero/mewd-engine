MEWD
====

MEWD stands for MADE ENTIRELY WITHOUT DOOM: a Doom-style engine, built
from scratch, with none of Doom's code or data in it.

The engine is MEWD; the game is MEWD Demo; the map editor is MEWD
Editor (at the user's request — it was Grocery Store Simulator and
GSS-EDIT).

A Doom-style game in which you walk into a supermarket at night with a
flamethrower and burn it down. Then the forest it stands in.

The store is SellWrong, the anchor of a strip mall — one long shed cut
into tenancies, with the big one in the middle paying most of the rent
and ten small ones either side hanging on. Four of them have a name on
the fascia and the rest never did. Seven of them you can walk into. All
of them burn. Round the lot is a perimeter road, and round that a wood
of thirty-five thousand firs and bushes, and that burns too.

AND ON THE OTHER SIDE OF THE ROAD IS THE TOWN whose main street the mall
killed: five by five blocks of it, a school, a church, and two hundred
and sixty-eight houses with an upstairs and an interior behind every
door that is drawn as a door. The fire crosses into it, climbs the
stairs, and goes through a party wall one house at a time. See TOWN.txt.

THE PAGE OPENS ON A TERMINAL, NOT THE GAME. Black glass, white VT323 type in a pale-ruled box with scanlines crawling down it, a
prompt that reads INTERFACE 2037, and nothing else on it at all — no
name, no date, no word of what it is or what it wants: it is a
password, and the only hint is the cursor. Every line it puts up is
typed out a character at a time, the way the ship's computer in ALIEN
talks, with a teletype tick under each character, a click under each
key you press, a buzz when it refuses you, a chime when it lets you
in and a hum under all of it, every sound synthesised in the page.
LAN PLAY, STEP ONE: THE SIMULATION BEHIND A MESSAGE INTERFACE (js/net/).
The player is no longer driven by the keyboard: every tic Game asks its
SESSION for a TicCmd (js/net/ticcmd.js) — turn, move, run, jump, use,
fire, weapon — and hands the player that. In single player the session
is this page's own input, rounded exactly as the wire rounds it
(seventeen bytes a command), so a player here and a player on another
machine are the same arithmetic; two hosts fed the same commands put
the player in the same place to the bit, which the test checks and
which client prediction will stand on.
  js/net/protocol.js   the wire: binary commands, JSON handshake and
                       snapshots; the map travels as { kind, seed }
  js/net/transport.js  one interface for a pipe: loopback (one process,
                       and the tests) and WebSocket (browser or Node)
  js/net/session.js    LocalSession (this page) and HostSession (a
                       client's commands, buffered, one a tic)
  js/net/server.js     SimServer: an authoritative Game and up to 16
                       lines, handshake, refusals, snapshots at ~12/s —
                       it does not care where it runs, which is how any
                       client will be able to host
  js/net/client.js     a client's end: hello, welcome, commands, snaps
THE DEDICATED SERVER: `node tools/server.mjs [--map jesse|maze]
[--seed N] [--port 7777] [--max 16]`. The real simulation with no screen
(tools/headless.mjs), a zero-dependency WebSocket at /net, and the game
itself served on the same port, so anyone on the LAN can open
http://that-machine:7777/. It prints the addresses to give out.
Why not a Web Worker, as first planned: a worker does not see the
page's import map, so the bare `three` import cannot resolve there
without a build step. The same result comes from hosting the SimServer
in the page itself (a listen server, which the app shell will do) or in
Node (the dedicated server).
LAN PLAY, STEP THREE: A PLAYER EACH. Start a host with
`node tools/server.mjs --map jesse` and open http://that-machine:7777/?join
in up to sixteen browsers (?join=host:port&name=ALICE for another host
or a name; or type `join`, or `join 192.168.1.20:7777`, at the
terminal).
  js/net/match.js      the rules. Team deathmatch on a map with teams
                       (JESSE: you join the smaller side and come back
                       on its own spawn pads) and deathmatch on anything
                       else (THE MAZE, with spawns found in the open
                       floor, and the crowd left at home). A frag for a
                       kill, one off for dying to yourself or the world,
                       a two-second respawn, two seconds of spawn guard,
                       first to 40 (team) or 20, eight seconds of
                       scores, then a new round. Your own side's rounds
                       go through you. The network loadout is the
                       minigun, at a third of its damage against a
                       person, and INFINITE: there are no pickups, so
                       every belt and tank is topped up every tic
                       (RULES.infiniteAmmo; single player keeps its
                       self-filling budgets): the other guns are built round one owner
                       and follow when they learn to belong to somebody.
  js/net/server.js     every client gets its own Player and session; the
                       map's START player is put aside. THE REWIND: each
                       command says which host tic the sender was drawing
                       the others at (`seen`, four more bytes: eighteen
                       in all, protocol 2), and while it runs that
                       command the host puts everybody else back where
                       they were then — up to a third of a second — so a
                       round hits what you saw. Snapshots carry all of
                       you, the others as [id, x, y, z, angle, pitch,
                       flags, team], the kills and joins since the last,
                       and the score once a second. A burst of commands
                       is folded rather than dropped, so the host never
                       loses a degree of where you are looking.
  js/net/remote.js     the browser's side. PREDICTION: your player moves
                       the moment you press; a snapshot puts it where the
                       host had it at the last command it got to, and the
                       unanswered ones run again on top. Both ends run
                       the same rounded commands, so this lands where you
                       already were — the test walks, runs and turns for
                       three hundred tics through a lagged line with no
                       correction at all. Only the host can hurt you.
                       THE OTHERS are drawn five tics in the past, slid
                       between the two snapshots either side, as troopers
                       off the sheets (SWAT for side A, the army for B)
                       that walk, turn, fire, fall and get up again; their
                       rounds leave holes, tracers and blood on this page
                       and hurt nothing. Kills go up as the gun's
                       notices, a win as the big card, the score along
                       the top, and the table while TAB is held.
  A match does not pause: the menu takes your hands off and the world
  goes on.
NOT SHARED YET: the rest of the world. Crates, fuel cans and fire are
each page's own, so what the rounds do to them is only very probably
the same everywhere. Next: those, the other guns, the in-page host and
the app shell.

JESSE, THE PvP MAZE (js/maps/jesse.js), typed as `jesse` at the
terminal, or ?jesse (?jesse&seed=N plays one again), or File -> Open a
new JESSE in the editor. Two fortifiable staging areas, one at each
end, joined by a massive multithreaded maze, and a different one every
time: 30-41 by 18-26 cells, cut into two to five zones along its length
that are each carved by their own algorithm (backtracker, Prim, growing
tree, binary tree, Kruskal) with their own walls, ground and share of
loops; several openings on every seam between zones; open rooms,
pillared halls and cloisters cleared across the corridors; and half the
time the whole maze point-symmetric. Every cell is reachable (a flood
knocks through anything cut off). The two bases are always mirror
images: a fort wall lower than the hedges with two to four gates, low
cover you can shoot over but not step onto, a tower up a stair that
sees over the fort wall, crates and fuel cans to barricade with, and
spawn pads for both teams in world.pvp. Same hedge-tile format as THE
MAZE, so it opens in the editor like any map.

WEAPON IMPACTS ARE DECALS AND NOTHING ELSE, at the user's request
(js/decals.js). No puff and no sparks where a round lands: a decal. And
every decal is a CUBE now — a box stood across the surface and drawn
from inside, whose shader reads the world's depth, rebuilds the point
of the world under each pixel and paints only what falls inside the
box — so a decal lies on whatever is there, wraps a corner, and stops
at the edge of a wall instead of hanging off it. The detail is all
arithmetic (noise, cracks, drops), not pictures, so it is sharp at any
size. One instanced draw for every decal of every kind:
  bullet holes    a dark bored core, a chipped lip, hair cracks, soot
  minigun holes   bigger, with a burnt ring, and the lip glows orange
                  and cools over a second and a half
  burning holes   what a rocket, the bore, a bomb, a barrel or a
                  molotov leaves: a crater with a molten rim and coals
                  flickering in the cracks, burning out over ~12 s into
                  char
  blood           a spatter at the feet of whoever is shot, thrown the
                  way the round went, and another up the wall behind
                  them if one is in reach; a POOL where somebody falls
                  or comes apart, spreading over its first seconds and
                  drying at the rim (the old flat GORE sprites are gone)
  heat, frost     the flamethrower's glow and the extinguisher's rime,
                  now with swimming flame and ice needles drawn in
The world's depth is copied once a frame (eight-bit packed) so the
boxes can read it while they draw; see Decals.draw and the afterWorld
hook in js/lofi.js.

THE LOGO is the user's MEWD mark (art/title-logo.png, their image with
its transparent edge cropped off), cut to four widths in assets/logo/
(mewd-480, -960, -1440 and -1951.webp) so the browser fetches the one
the screen needs. It is small on the loading screen and BIG over the
title: nearly the width of the glass, and as much of its height as
leaves room for the menu.

THE TITLE HAS ITS OWN LEVEL: grass and pines seen from the side, sliding
past right to left for ever, a quarter as fast as it first went, at the
user's request (js/titlescene.js). SEVEN ROWS OF GRASS from under the
eye back to the trees and SEVEN ROWS OF PINES behind them, each row of
pines taller than the one in front. NO GAPS by arithmetic: every row
reaches high enough to hide the roots of the row behind it, twice over,
and its plants stand closer than a third of their height so they
overlap; a dark band stands behind the last pines. A real perspective
camera moving sideways does the parallax, and each row is a ring that
re-dresses whatever falls off its left end as a different plant at a
different size. The wind is AGGRESSIVE: gusts rolling along the rows, a
sway and a whip at the tips, the grass bending hardest. Under the top
half of BSKY1, on GRASS5. THE LAYERS,
top to bottom, at the user's request: the HTML menu; MEWD, the page's
own HTML logo, in front of the dither and never snapped; a blue
overlay; the game's dither and palette LUT; the logo's shadows; a
monochrome filter; the forest. The forest's materials write grey (mono
in js/titlescene.js), and the blue is multiplied over the finished
frame by the pipeline's last pass (LofiPipeline.tint, white everywhere
but the title) — over the dither, because the palette has no blue that
saturated and under it the wash came out slate. BLUE is the logo's own,
the bright circuit lines in its letters (about #3e5ebe) scaled so white
grass is that blue. Behind the logo, for contrast, its outline blurred
and black twice over: a tight drop shadow down and right and a wide
dark halo (shadowOf), drawn into the frame over the box the page's logo
takes (TitleForest.loadLogo / placeLogo), under the dither; a real
perspective camera moving sideways does the parallax, and each row is
a ring that re-dresses whatever falls off its left end as a different
plant at a different size. It is drawn through the game's own pipeline
and thrown away when NEW GAME is taken.

THE VEGETATION MOVES IN THE WIND, at the user's request, in the vertex
shader. In the game's wood (PLANT_VERT in js/forest.js) every plant's
top is pushed downwind and let back, the root fixed and the push going
as the square of the height: a slow lean that rolls across the wood as
a wave, so a gust visibly travels downwind, a flutter of each plant's
own, and a gust that comes and goes. Which way and how hard is the
weather's wind (climate.wind): a still night barely stirs the leaves, a
storm bends the firs. A burnt plant does not sway. It is a shear of
the four-vertex quad, since the wood is vertex-bound. The title's forest
bends properly — its cutouts are six strips tall — with the grass
curling most and the far treeline barely moving (the `sway` of each
row in js/titlescene.js).

A PHONE HELD UPRIGHT IS AN ERROR, at the user's request: the whole screen
goes red, over the terminal, the title and the game alike, with a black
rotate glyph (Material Icons' screen_rotation, inlined as its path so
nothing is fetched) and ROTATE DEVICE, until it is turned. A phone is a
coarse pointer, so it shows before the game has even loaded. It replaced
the quiet line at the top that used to suggest turning it.

THE MAIN MENU is Doom's, in this game's clothes: NEW GAME, CONTINUE,
LOAD GAME, OPTIONS, MULTIPLAYER and QUIT GAME in a column under the
logo, the one you are on filled in red with a blinking marker. Up/down (or W/S) walk
it, enter, space or a click takes it. Only NEW GAME goes anywhere yet;
the rest are dimmed and shake their heads. On a phone held sideways
the logo takes the left of the screen and the menu stands at its right.

THE NAME IS MEWD, at the user's request: Doom backwards, misspelt, and
what the logo says. Every DEWM in the page, the manifest, the terminal,
the editor and the comments is MEWD now; the terminal's prompt still
reads INTERFACE 2037.

THE LANCE NO LONGER CHANGES THE LEVEL, at the user's request. It cuts no
holes, fells no buildings and lights no street; the column stops at the
first wall, floor or ceiling it meets (BeamSystem._impact) and SEARS it
instead — one enormous burn, 170, 240 or 320 units across by the charge
it was fired at, glowing and then cooling to a charred crater with
orange cracks, and a scatter of slag splashes round it leaning the way
the beam was going (BeamSystem._sear, SEAR in js/beam.js). It still
kills and lights everybody between the muzzle and that wall.

HOLES LAST FOUR TIMES AS LONG: the ring keeps 400 of them, up from 100,
and blood 480, up from 120 (js/decals.js).

BLOOD GOES UP THE WALLS: a hit sprays four rays in a cone behind the
victim, 24 degrees each side of the shot and 260 units long, and every
one that meets a wall leaves a spatter on it (sprayWalls). Gore that
hits a wall now lies on the wall rather than as if it were floor.

A ROCKET TAKES PEOPLE APART (Giblets.eviscerate, GORE in js/people.js):
everyone a blast kills goes up as sixty chunks thrown out from the
blast and trailing blood, ninety particles of mist and drops (their own
pool, Effects.bloodSpray), a pool where they stood, a dozen spatters
across the floor and twenty rays of blood up every wall within 360
units — and a trooper always plays the gore death, however much health
they had.

THE DEMO IS A MAZE, at the user's request: MEWD Demo opens on a hedge
maze generated afresh every time the game starts (js/maps/maze.js) —
18 by 18 corridors carved by a depth-first walk, braided so there is
more than one way round, with paved plazas cleared in it (a lamp in
each corner, a tree in the middle) — and over five hundred people
wandering it. ?seed=N plays maze N again (the seed is in the console);
?sprawl is THE SPRAWL, the world it used to be. The maze is a MEWD
Editor document like any other: File → Open demo: a new MAZE opens one
in the editor, and File → Open THE SPRAWL the old one.

Every entry is refused with the same two lines — UNDEFINED COMMAND /
SYNTAX ERROR, and the entry REFUSED — but these, at the user's request,
in any case:

  G  or  GAME     the game (js/main.js boots it; the terminal fades off
                  in front of the loading screen)
  E  or  EDIT     the map editor: see MEWD Editor, THE MAP EDITOR below
  QUIT  or  EXIT  leaves for news.asr.institute

Nothing under js/main.js knows the terminal exists.

Open index.html in a browser. No install, no build step. Every texture,
every sprite, every sound and the whole level are generated in the page
at start-up, in about a second and a half — it was half a second before
there was a town, and a town is ten thousand regions. What it loads is
what was made somewhere else: the people, the trees, and the gun. The
sky was a photograph and is generated now, for the hour and the
weather.

  TOWN.txt              the plan for the town round the mall: a street
                          grid, a school, a church, townhouses of two
                          and three storeys with interiors — and the
                          one engine idea all of it waits on, which is
                          that a sector may name the sector above it.
                          Nothing in it is built
  SIGHT.txt             the plan for the air between you and the thing
                          you are looking at: occlusion, fog, a sky that
                          changes, a fog that matches it because it is a
                          texel of it, LOD, the cull distance, time of
                          day and weather — one system, because they are
                          one. Nothing in it is built either
  .gitlab-ci.yml        test, then publish to GitLab Pages
  .github/workflows/    the same two jobs, for GitHub Pages
  index.html            the page: the terminal, and the game under it
  js/terminal.js        the terminal — the password in front of the game
  css/style.css         the furniture around the frame, and the thumb controls
  manifest.webmanifest  what a phone calls it when it is added to a home screen
  icon.png              and what it draws there — node tools/bake-icons.mjs
  vendor/three.module.js  three r160, local so the game runs off a memory stick
  js/maps/town.js       the town: the grid, the houses, the school and
                          the church. See TOWN.txt for the plan and for
                          where this departs from it
  js/                   the game — js/weather.js, js/skyart.js and
                          js/rain.js are the hour, the weather and the
                          wind; the sky baked in the page for them; and
                          what falls out of it. See THE AIR, THE HOUR AND
                          THE WEATHER, and WHAT YOU CAN SEE.
                          js/standees.js and js/lamplight.js are the
                          newest: a crowd in one draw call per picture,
                          and the flare at every street lamp after dark
  art/                  the logo, the old sprite weapon, the seven four-view
                          vehicle sheets and the atlas packed out of them —
                          which nothing loads any more — art/people/, the
                          SWAT sheet and the army sheet as the user drew
                          them, and art/uzebox.hex, the console palette the
                          second box of crayons is checked against
  assets/people/        the crowd, and what is left of one: seventeen
                          shoppers, eleven pieces, three splats, a fireball;
                          the squad, fifty-one cells of SWAT; and the army,
                          fifty-one cells cut the same way
  assets/forest/        the wood: ten plants with their burn maps, two
                          grounds — and the town's six broadleaves, baked
                          into the same format by tools/bake-plants.mjs.
                          The block of clipped box is still there and is
                          no longer loaded: the hedges are geometry now
  assets/sky/night.png  the night as a Polyhaven photograph, which the game
                          wore until the sky was generated (js/skyart.js);
                          kept, no longer loaded, no longer shipped
  assets/models/        the flamethrower, the fire extinguisher rifle and
                          the cerebral bore, all three Vaportrash's and all
                          three stripped by tools/prep-model.mjs; the
                          minigun, the user's own, stripped by the same tool
                          with its emission marker read into the file's
                          extras and its barrel set named there; the van,
                          the police van and the army's hover APC, which
                          are the user's three — the APC stripped by the
                          same tool, two megabytes of normal and
                          metal-rough off a renderer that has no lighting
                          model to spend them on; and the VTOL gunship,
                          the user's fourth and the only one that never
                          touches the road, with the two marker spheres
                          the user drew inside it read into its extras
                          and its sheet crunched from 2048 to 1024 —
                          six megabytes of its seven, at the user's
                          request
  assets/fonts/         Michroma (SIL OFL), the title face
  assets/music/         the user's three E1M1 remixes, mixed on the beat
                          by js/music.js
  tools/bake-art.mjs    node tools/bake-art.mjs — turns art/ into source
  tools/bake-plants.mjs node tools/bake-plants.mjs — turns art/plants/
                          into the pair of PNGs the wood plants
  tools/prep-people.mjs the crowd's art, crunched down from galvarius
  tools/prep-troops.mjs a troops sheet — the SWAT's or the army's — found
                          cell by cell and cut into a strip
  tools/prep-forest.sh  copies the wood's art over from the golf project
  tools/bake-sky.mjs    the sky as it used to be made: 8k panorama to 1024
                          palette pixels. Its reasoning about dither is
                          what js/skyart.js is built on
  tools/prep-model.mjs  a .glb down to what this renderer binds: the colour
                          map, four attributes, one tight view an accessor
                          — and marker spheres out of the mesh and into
                          the file's extras, for a model that has them.
                          --texture N halves the colour map until it is
                          N or smaller, which is the gunship's six
                          megabytes down to one and a half
  tools/build-site.sh   assembles public/ — what actually gets published
  tools/bake-icons.mjs  the home-screen icon, out of the game's own fire
  tools/smoke-test.mjs  node tools/smoke-test.mjs — no install, no browser


DEPLOYING
---------

It is a static site with no build step, so publishing it is a copy. What
gets copied is not the whole repository: the untouched Freedoom frames
the apron is painted over, the source PNGs for art already baked into
js/art-data.js, the tools and this file are all repository, not site.
tools/build-site.sh is the one definition of the difference, and both CI
files call it rather than each keeping a list that can drift. The smoke
test assembles the site the same way into a scratch directory and checks
that every asset path the page's own source loads is in it, so a copy
that leaves something out fails the test rather than the live game.

The repository setting has to agree with all this: Settings > Pages >
Source must be GitHub Actions. Set to deploy from a branch instead,
GitHub builds the branch with Jekyll and publishes the whole tree, this
file and the tools included, over the top of the artifact the workflow
uploaded — the site works, but it is not the site the script defines.

Both pipelines run the same two checks first, and the deploy DEPENDS on
them rather than merely following them — a broken build that reaches the
URL is worse than no deploy, because nobody files a bug against a game,
they close the tab.

  the smoke test         2612 checks, no install and no browser
  art is in step         re-bakes art/ and fails if js/art-data.js moved

That second one exists because baking the logo and the weapon into source
by hand is what buys the no-build-step property, and a hand-run step is
only safe if something notices when it has not been run. Otherwise a
re-exported logo sits in the repo looking authoritative while the game
goes on drawing the old one.

There is no npm install anywhere on purpose: the smoke test stubs three.js
itself and nothing else in the repo has a dependency, so a pipeline is one
container pull and about a second of work.


WHAT YOU DO
-----------

YOU START ON THE CLOCK, at the user's request: in the well of the middle
checkstand, at night, facing west across the scale plate at whoever is
next. There is somebody's shopping coming up the belt on your left, a
register at your elbow, a queue of five out past the lane light, and a
shop behind you that you can see the whole length of because you are
standing at the front of it.

It used to be the mouth of the car park, across the road, which is the
establishing shot: this is a supermarket. The till says the thing the
establishing shot cannot, which is that it is YOUR supermarket and you
are at work in it. You still get the other one — it is thirty seconds'
walk and you have to go out past the queue to take it.

There is no goal. Burn what you like — the store, the wood behind it,
both — and see what the night brings down the road. The sixty-per-cent
target and the run back to the car park are gone, at the user's request:
the only aim for now is open mayhem, and the night ends when you close
the tab.

There are seven hundred and thirty-six people in the shop and six fire
exits for them to get out of, so the shop empties: light one aisle and
most of the building is in the car park or in the trees inside a minute.

THE CORNER IS TWO BARS UNTIL SOMETHING HURTS YOU, at the user's request.
It used
to be four numbers — how much of the store had gone, how much of the
wood, how many were left, how much was in the tank — with a running list
of notifications under them, and all of the words are gone. What is left
is the two gauges that were already drawn under the numbers: the store
burning, in fire colours, and whatever is in the thing you are holding.
The count of the living went with the text and went on purpose; a bar
cannot say a number and the shop on fire in front of you was always the
better readout anyway. From the first hit it is five: the two gauges and
the three layers of you — see AND YOU CAN BE HURT NOW.

AND THE READOUT IS NOT PART OF THE PICTURE ANY MORE, at the user's
request: it is its own canvas over the frame, at the screen's own
resolution, outside the pixel filter entirely — see THE READOUT CAME OFF
THE PICTURE.

  WASD          move            MOUSE     look
  SHIFT         run             LMB/CTRL  fire
  SPACE         jump            WHEEL     cycle weapons
  F             open, use
  1 - 7         flamer / extinguisher / bore / minigun / lance /
                quad launcher / arc maw
  Z  C  RMB     put the scope to your eye: the lance's screen, or the
                launcher's thermal sight
  [  ]          render size     SHIFT [ ] pixel size
  N             palette on / off          ESC       pause
  IN THE MENU:  arrows turn the page, or move an open window's slider;
                escape closes the window, then the menu
  `             the frame-rate readout, off by default

GAMEPAD, laid out the way every shooter lays it out, at the user's
request — it was briefly the other way round, and the user asked for
the standard:

  LEFT STICK    move            RIGHT STICK  look
  R2            fire            L2           jump
  L1 / R1       previous / next weapon
  A             use             L3 / R3      run

And a pad in use takes the phone's thumb controls off the picture — see
ON A PHONE. Mouse look needs a click to grab the pointer. On a phone
none of the keyboard applies and the next section is the one that does.

THERE IS MUSIC, at the user's request: the user's three E1M1 remixes
(assets/music/, four files arrived and two were the same file byte
for byte), one into the next into the next and round again for ever,
each fading into the one after it ON THE BEAT. Nothing is analysed
while the game runs: each track was measured once, offline, in the
same decoder the browser uses — tempo to a hundredth, the downbeat at
the head, a downbeat in the last forty seconds to hand over on — and
the answers are a table at the top of js/music.js. On the outgoing
track's handover downbeat the incoming's first downbeat lands, both
gains ramp LINEARLY over eight bars, one up and one down, and the
outgoing stops. And the incoming arrives at the OUTGOING'S TEMPO —
the three are 145.8, 140.3 and 142.3, and a fade between grids four
per cent apart flams by a quarter of a beat before it is half done —
with its playback rate set to the ratio, so its bars are the other's
bars for as long as both can be heard, and then eased back to one
over eight more bars, which is a DJ's pitch fader going home. All of
it is Web Audio's own clock, sample accurate. A MUSIC fader is in the
pause menu and remembered; the music has its own context, so the
switch below does not take it.

AND THE SYNTHESISED SOUND IS OFF, for now, at the user's request:
MUTED at the top of js/audio.js is one switch, and with it on play()
refuses every made-up noise and the ambience never starts, so every
sound in the game is still asked for and none of them is made. Flip it
and they are all back. WHAT IT DOES NOT SILENCE IS A RECORDING: the
minigun arrived with three of its own, the user's, in assets/sfx/ —
the spin-up, a two-second loop of it firing, and the wind-down — and
they play whatever the switch says. The player asks for 'spinup' the
way it always did and js/audio.js hands back the recording (see
SAMPLE_FOR); the firing is one held sound, looped from the first round
to the last and stopped with a short ramp when the trigger comes up
or the belt runs dry (see Player.gunLoop). And they are turned DOWN
(SAMPLE_GAIN, a fraction a recording): as recorded the minigun drowned
the three tracks the user mixed, so the loop plays at a third and the
spin-up and wind-down under half, and the music stays where its fader
puts it.

THE LOADING SCREEN SAYS RETICULATING SPLINES, at the user's request, and
nothing else, for the whole of the half second; the bar still moves.
And nothing is written across the middle of the picture any more — the
SIRENS and THE ARMY IS ON THE ROAD cards that used to announce a convoy
are gone, at the user's request. The siren says it. The one card left
is the one that ends the night.

One weapon, and it is a flamethrower: a STREAM. Hold the trigger and
six fireballs a tic leave the nozzle at a thousand units a second, in a
line rather than a string of beads, slow in the air, drop, and set fire
to whatever they land on — seven hundred units of reach, on the floor
about four hundred out if you fire level, further if you lift it. Drawn
additively, so where they overlap they add up to a white-hot core and
the whole arc reads as one unbroken tongue. It goes where you point it
and no further, which is the whole feel of the thing.

THE TANK EMPTIES, at the user's request, and nothing in the shop refills
it. It holds twelve seconds of flame with the trigger held down, and it
fills itself at one unit every ten tics — a full tank in two minutes. So
a second of firing costs ten seconds of walking, and the honest way to
play is short bursts a long way apart. The forty-two fuel cans that used
to be laid out over the shop floor are gone with it: a can on the floor
and a tank that regenerates are two answers to the same question, and
having both means the regeneration never matters.

AND IT WILL NOT LIGHT AGAIN UNTIL IT IS HALF FULL, which is the knob that
turns that budget into a decision. A tank that refuses only when it is
empty is a tank you hold the trigger on until it stops and then hold it
again the moment one unit has trickled back: twelve seconds of flame
becomes twelve seconds and then a stutter of tenths, and the ten-seconds
of-walking-per-second-of-flame arithmetic never actually bites. A tank
that will not light below half is a tank you have to WALK AWAY FROM for a
full minute — and that minute is the one the fire you have already set
does its own work in. It latches on empty and clears at half, so the
gauge only ever has two things to say, and while it is latched the fuel
percentage on the status bar is replaced by the mark it is climbing to
with a pip on the bar where that is.

THE BOXCUTTER IS GONE, deleted at the user's request, and the third
weapon is the CEREBRAL BORE — see THE CEREBRAL BORE below — and the
fourth is THE MINIGUN, see the section of that name. Mouse wheel, or
1, 2, 3, 4. The molotov is written, tested and still switched off. The
player cannot be hurt BY FIRE — that is one flag at the top of js/player.js, FIREPROOF, and it
used to be the whole of the player's invulnerability. A bullet gets
through it now, because there are bullets: see THE ROAD, AND WHO COMES
DOWN IT.

AND THERE ARE TWO SWITCHES IN THE PAUSE MENU THAT TURN ALL OF THAT OFF,
AND BOTH ARE ON BY DEFAULT, at the user's request, until turned off
there (the choice is kept; the prefs version went to 5 so a saved
"off" from before the default changed is not kept alive).
DEBUG: INFINITE AMMO fills every tank — the flamethrower's, the
extinguisher's and the molotovs — back to the top once a tic, so nothing
ever empties and neither latch ever catches. It is for looking at the
place rather than for playing it: with the fire as slow as it now is,
walking the whole shop to see what it looks like burnt should not also
be a two-minute wait every twelve seconds.

DEBUG: INVINCIBLE is the other one, at the user's request, and it is the
same shape: one branch, at the top of Player.damage, which returns. Every
way the player can be hurt arrives there — the rifles, the vans, the fire
FIREPROOF already refuses — and the only way out of the level dead is the
health check at the bottom of that same function, so refusing it is the
whole feature and nothing else in the game knows the mode is there. It
takes the SHOVE with it, because being knocked sideways by a van is part
of being hit by one. And it is NOT a heal: turn it on at forty health and
you stay at forty for ever, which is the honest reading of the word and
keeps one switch from quietly being two. It is what makes the squad
watchable — nine vans and eighty troopers is a fight you lose in about
fifteen seconds, and looking at it is a different job from surviving it.

INFINITE AMMO IS ONE BRANCH, in Player.fuelTic, and that is deliberate.
Everything that asks a question about ammunition — whether the trigger works,
whether the gauge is red, where the refire pip sits, whether the gun is
latched — reads the tank, and the refill runs once a tic upstream of all
of them. So the spending still happens exactly as it always did and is
simply undone before anybody looks, and not one line anywhere else in
the game knows the mode exists.

WHAT IT SAYS ABOUT THE LANCE IS NOTHING, NOW, and it is worth keeping
the story of why it ever had to.

The lance used to be limited by HEAT rather than by a tank, so a switch
that only refilled tanks left the one weapon in the game it did not
touch, and this branch had to say something about temperature to mean
anything. The first cut said the coil was cold — setting lanceHeat to
zero here — and since this branch runs once a tic with the switch ON BY
DEFAULT, the number the chassis glow was drawn from got wiped before it
ever reached a frame. The gun never glowed in an ordinary game at all,
and the user reported it as the shader not working. The shader was fine.
The repair was to clear only the LATCH, which is what armed() reads, and
leave the temperature alone, which is what the shader reads.

All of it is moot: at the user's request the lance has no heat, no latch
and no temperature (see DIALLED BACK), and the cell IS its limit, so the
loop above has already filled it and there is nothing special left to
say. The lesson survives the feature — a debug switch that has to reach
into a system to mean anything is a debug switch that can break it.


AND THE OTHER END OF IT
-----------------------

THE SECOND WEAPON IS A FIRE EXTINGUISHER, at the user's request, and it
is a rifle built out of one — somebody else's model, dropped in as it
stands the way the van was. Slot 2. It is the same KIND of thing as the
flamethrower, deliberately: a stream, billed per tic of pour, on its own
tank with its own latch, so the two are held the same way and used
against each other.

WHAT IT OBVIOUSLY DOES is put fires out. The jet takes heat out of the
fuel grid where it lands and out of the wood if it lands there, and it
clears the ember clock with it — the difference between a fire that is
out and a fire that is sulking, because a cell left at a glow relights
anything that wanders past. It is a shorter arm than the flamethrower,
four hundred units against seven hundred, and it sinks harder: cold gas
is heavier than the air it is in, so the jet pools along the floor where
it lands, which is where the fire is.

WHAT IT CANNOT DO IS UNDO ANYTHING. Fuel that has burned is burned, the
store's percentage never goes backwards, and a charred aisle stays
charred. So it is not an undo button, it is a firebreak you can draw
with, and the thing it saves is whatever has not caught yet.

AND IT FREEZES PEOPLE. Enough gas on one and they go solid: a blue
statue that stops running, stops burning if they were burning, and
BLOCKS THE AISLE for everybody behind them. Three things can then happen
and the player picks:

  leave them    the frost bleeds off over about seventeen seconds and
                they thaw, get up and run — which is the outcome that
                makes freezing somebody a decision rather than a slower
                way of killing them
  burn them     fire on ice is an execution. They stay exactly where
                they are, an ember front eats the drawing from the feet
                up, and about three and a half seconds later there is a
                heap of ash on the lino. A fire anywhere near their feet
                does it as well as a direct hit — it reads the heat of
                the CELL they are standing in, so a store that is
                burning does this to its own frozen people as it goes
  break them    anything at all that hits a frozen person shatters
                them, whole, into bloody frozen chunks

AND NOTHING ELSE GETS THEM OUT OF IT, which is what makes that a list of
three rather than a list of three plus whatever happens to go off nearby.
Being frozen is a HOLD, and so is being eaten: for as long as either one
lasts, every system in the game that makes people react is refused. A car going up forty units away,
the noise of the player's own trigger, a neighbour sprinting past — all of
them used to reach past the ice and set a block of it running, still
solid, still blue, with ninety of its hundred frost still on. The lock is
one line in Actor.setState, which is the single door all of them came
through, and the two functions allowed to overrule it are the two that
own the ice. A fright that arrives while somebody is held is dropped
rather than queued, and a fresh one is handed to them on the way out —
what you should run from is what is there NOW.

THE TWO WEAPONS TOGETHER ARE A THIRD THING, which is the point of the
second one. Fire used to MELT a frozen shopper free and set them running,
which made the flamethrower the undo button for the extinguisher: a
player could spoil their own freeze by sweeping the aisle a moment later.
Turned round, the pair are a combination — freeze one, burn them, and
they are gone where they stood. No fireball, no thirteen pieces two
aisles over, nobody else running. With the shatter that is two quiet ways
of emptying an aisle, and quiet is the thing the flamethrower alone can
never be.

AND YOU WATCH IT HAPPEN, which is the other half. Nothing else in this
game kills a person slowly enough to look at: a shopper the stream
touches runs for five seconds and explodes, and a frozen one hit with
anything solid is thirteen pieces in a single frame. This one takes three
and a half seconds and the whole of it is on the drawing — a line of
coals crossing them from the feet up, the coat and the shape going with
it, the body settling as its legs stop being there, and a heap of ash and
a few embers left on the floor. It is done in the sprite shader rather
than in art, because seventeen shoppers times an animation of a person
burning away is art nobody is going to draw, and because the drawing
being EATEN — their own coat, their own silhouette — is what makes it
read as that person rather than as an effect played over them.

ONE RULE, HOWEVER THE FIRE ARRIVES. A flame particle, a car going up
beside them, or simply the floor they are standing on being alight: all
three do the same thing. That took a fix — the fire system lights
anything standing in a cell over 70 of 255 and the thaw was reading heat
from a fifth of that, so there was a window in which a block of ice at
the EDGE of a fire melted free while one in the middle of it was eaten.

THE COLOUR IS A MAP AND NOT A TINT, which is the difference between
somebody frozen and somebody with a blue light on them. Multiplying a
red coat by blue gives a dark muddy coat; what a person inside a block of
ice looks like is their SHAPE in ice. So the texel's luminance is kept,
everything else is thrown away, and that one number runs up a ramp from a
deep shadowed blue to a pale lit one — a red coat and a green coat come
out as the same ice at different brightnesses, which is exactly right.

SHATTERING IS QUIET, and that is the mechanic rather than an oversight.
A person going off in flames is an explosion: a fireball, heat into the
floor, and everybody within nine hundred units running. A person
shattering is a crack and a scatter, and the shopper four feet away
carries on looking at the beans. A player who wants to clear an aisle
without starting a stampede now has a way to do it, and it is the only
way there is.

THE TWO TANKS ARE NOT THE SAME TANK. The flamethrower holds twelve
seconds and fills in two minutes, because fire is the thing the game is
about and should be rationed. The extinguisher holds seven and a half
and fills in thirty, and comes back at a third rather than a half,
because putting a fire out is defensive, is usually done under time
pressure, and an extinguisher that is empty when the aisle you wanted is
alight is a weapon that exists to disappoint.

AND THERE IS A HOOK FOR A WEAPON THAT DOES NOT EXIST. Something physical
is coming — a bat, a hammer, whatever it turns out to be — and the half
of a weapon that is hard is not the art, it is the question of what a
swing MEANS to the rest of the game. Game.impact is the answer, written
and measured ahead of the thing that will call it: a short reach, a wide
arc, the nearest thing in it, and a DIRECTION. That last one is the new
part. The shatter itself needed nothing — a blow on a frozen person was
already a shatter, because everything that is not fire is — but the
pieces now go the way the blow went, in a sixty-degree cone either side
of it and harder the heavier the swing, which is the difference between
being hit and coming apart on your own. It hits people who are not
frozen too, as ordinary damage, because breaking is a property of the
ICE and not of the weapon. It does not push anybody: actors in this game
have no momentum, they move a whole step or none of it, and knocking a
shopper across an aisle would be a physics system rather than a
parameter. When the weapon arrives it is an animation, a table entry and
one call.

THE BOXCUTTER USED TO SWING THROUGH IT and is deleted; the hook stays,
and the smoke test swings through it directly so it is not rotting while
it waits — a blow with a direction on it through a block of ice throws
the pieces down the aisle in front of you instead of dropping them in a
ring.


THE CEREBRAL BORE
-----------------

TUROK 2'S, at the user's request, and the user's model: assets/models/
bore.glb, stripped of the normal and metal-rough maps by
tools/prep-model.mjs the way the flamethrower was — half of what it
weighed — and held low and right like the other two, a third smaller
and a third farther from the eye than they are (at the user's request:
it is a big square thing and at the flamethrower's size it was a
quarter of the picture). Both numbers are the gun's own in GUNS rather
than a change to VIEW, and "farther" is a push straight back along the
view, z alone — the first try scaled the whole position along the line
from the eye, which keeps a point's place on screen and did, for the
gun's centre, which is below the bottom of the frame by design, so the
launcher shrank around a point nobody can see and all but left the
picture; see WHAT WENT WRONG. It is the one weapon in the game that is
AIMED rather than poured, and the rules are Turok's; js/bore.js is the
whole of it.

THE SIGHT. Every tic the bore is in hand a ray goes out of the eye along
the view, pitch and all — the flamethrower's aim never needed the pitch;
this one stops at the floor when you look at your feet — to the first
wall or the first body. A red line is drawn from the mouth of the
launcher to that point and a dot put on it. When the point is a person
the dot becomes a reticle on their head and you are LOCKED: a beep, and
the reticle stays with the head for fourteen tics after the beam leaves
it, because a sight that drops the lock the instant you twitch is a
sight you fight rather than use. Anyone alive and shootable with a head
can be locked — the crowd, the squad, a block of ice with somebody in it
— and not a van.

THE TRIGGER DOES NOTHING WITHOUT A LOCK. That is Turok's rule and the
whole feel of the thing: it is not a gun you point, it is a gun you wait
with. The refusal clicks, once a press, because a trigger that does
nothing at all is a trigger you press harder. Five in the magazine and
one back every twelve seconds — the slowest thing in the game to refill,
because it is the only thing that never misses: a lock is a kill, so what
the magazine rations is kills.

THE FLIGHT. The bore leaves the launcher along the line of sight, slowly,
and every tic bends toward the head it was sent to by at most nine
degrees while it speeds up threefold — so it leaves in a curve and
arrives fast, which is the shape of the thing in the original. It stops
for walls, floors, ceilings and the target's head and nothing else; a
target that dies on the way is a target it flies straight past and rings
off a wall.

THE DRILL is the third HOLD, after the ice and the burn-away (see
Actor.held): two seconds of standing exactly where they were, shaking —
a drawing offset, fresh every frame, a fit rather than a sway — while
the bore sits in the skull turning and what was in there comes out of
the top in a fountain. The fountain is the crowd's own gore pieces at
half size and a fifth of the speed, carrying a flag that says they were
never alight, so they trail no fire and land as blood rather than
sparks; and a red mist over it out of the smoke pool. Nothing scares
them, nothing hurries it. A block of ice the bore reaches shatters
instead; somebody half ash is finished.

AND THEN THEY EXPLODE — the same coming-apart the flamethrower gets, the
fireball and the thirteen pieces for a shopper and the gore animation
for a trooper, because "explode" already means one thing in this game
and the bore should not teach it a second one. The kill is the player's,
and a kill is what calls the SWAT.


THE MINIGUN
-----------

THE FOURTH WEAPON, at the user's request, and the user's own model:
assets/models/minigun.glb, twelve and a half megabytes as it arrived
and seven and a half after tools/prep-model.mjs took the normal and
metal-rough maps off it. Slot 4, or the wheel, or SWAP. And it is the
first model since the old flamethrower to carry its own answers, in
its own node names: a marker cylinder named for the emission point,
which the tool takes out of the mesh and writes into the file's extras
as the nozzle (through the node's own scale, quarter-turn and
translation, because the cylinder sits thirty units up its own node's
y), and a barrel set named to be ROTATED, which the tool leaves in and
names in the same place. js/weapon3d.js reads both back: the nozzle is
where the muzzle flash sits and the rounds are born, and the barrel
set turns about its own z.

ABSURDLY DESTRUCTIVE, which was the specification. Four rounds a tic
out of a belt of three thousand — a hundred and forty a second for
twenty-one seconds with the trigger down — each one a hitscan of
twenty-four to forty-eight, which is two to four times a shopper and
enough of them, in a burst, to open a van. It goes where the eye
looks, PITCH AND ALL: Game.hitscan grew a pitch for it, since a rifle
that fires level was fine for a trooper and is not fine for a gun you
point at the floor of the car park. The belt fills itself a round a
tic and latches at a quarter, on the tanks' terms and for the tanks'
reason. Infinite ammo fills it like the rest.

AND IT SPINS UP, a third of a second from the trigger going down to
the first round, and eight tenths to stop after it comes up — the
barrel set on the model turns to match, and js/audio.js has a sawtooth
for each direction. A dry belt does not spin, because a spin that
leads to nothing is a promise the gun cannot keep. AND IT HEATS: four
seconds of fire takes the barrel material from cold to the yellow-white
of steel that should have stopped, dull red first from the muzzle
back, then orange, then white; seven seconds of not firing brings it
back. It is one uniform on the one material the barrels wear, banded
like the rest of the gun's light, and nothing else happens at the top
— the glow is the whole of it, at the user's request — but the gun
tells you how long you have been holding the trigger, which a belt
gauge in a corner only says in a corner.

WHERE IT SITS WAS DRAWN UP SIX WAYS BEFORE ONE WAS PICKED, at the
user's request, off the same scene the game draws. The model's own
centre is well back in its body, so held close (like the flamethrower
used to be) everything but the barrels drops off the bottom of the
picture; held dead centre at the hip it is a grey tube; held out far
enough to see the whole thing it is a toy. The user picked the CORNER:
GUNS.MINIGUN in js/weapon3d.js holds it on VIEW's own hold like the
streams, a quarter longer than the flamethrower and a little nearer,
so the receiver fills the corner and the barrel set comes in across
the lower right quarter of the picture, the way the old flamethrower
did. The other five are the same two numbers (fit, out) plus an offset
(pos) and a turn (rot), and any of them is a one-line change.

AND NO DISC ACROSS THE MUZZLE, any more. It had one for a while, at
the user's request — the same fire frames turned to face the eye,
additive, spun every frame — and then the user asked for it gone: the
tracers start at the end of the barrel now and are very long, and a
line of light drawn out of the gun says it is firing better than a
flash in front of it did. The two crossed tongues stay, as on every
gun.

THE HUD SAYS WHAT YOU ARE HOLDING, small, top right, at the user's
request — the one word the readout has grown back since the corner
went to bars. Four weapons that all cycle off one button on a phone is
one too many to keep track of by the shape of the barrel.


WHAT THE WEAPONS LEAVE ON THE WALLS
-----------------------------------

THREE KINDS OF DECAL, at the user's request, and they are one system,
js/decals.js:

  HOLES    where a round lands on a wall, a floor or a ceiling: a dark
           core inside a ragged pale lip — the chipped plaster, which
           is what you actually see, because the shop is dark at night
           and a dark spot on a dark wall is nothing — a hand across,
           turned at random. FOUR HUNDRED of them now (a hundred before) — the MAX
           COUNT, at the user's request, down from five hundred and
           twelve, because the accumulation was costing a frame it
           should not have — and when the ring is full THE OLDEST FADE
           OUT, IN ORDER, at the user's request. Not on a clock of
           their own: the two dozen slots at the old end are held down
           to their PLACE IN THE QUEUE, nothing for the one about to be
           overwritten and nearly full for the one at the back of the
           band, so a hole fades as the cursor comes round to it
           however fast the trigger is being held. Under the minigun
           that is a tail of dissolving holes behind the burst; with
           the trigger up it is the oldest few going out and the rest
           standing. Nothing is ever cut off the wall at full strength,
           which is what the old ring did four times a tic. The heat
           and the frost are rings on the same rule, capped at the same
           hundred, on top of their own cooling and thaw; the scorches
           share the holes' ring. The troopers' rifles leave them too,
           and so does the gunship's vulcan. AND THEY ARE
           CULLED: a hole past DRAW_RANGE (2600 units) from the eye, or
           behind the plane the eye looks along, is not written into
           the buffer at all, so a shop shot to pieces costs nothing
           until you turn round and look at it. The buffers are
           rebuilt every frame, compacted to what is in view, with no
           allocation in the loop. And the PUFF a round throws where it
           lands — the same small sprite as the blood off a body — is
           centred on the hit now: its picture's lift was a full height
           and a half, so every hole had its puff floating above it,
           which the user saw. See the PUFF frame in js/sprites.js.
  HEAT     SPOT HEATING for the flamethrower: where the stream lands,
           the surface itself glows, and the longer the stream is held
           on one spot the hotter the spot — dull red, orange, the
           yellow-white the minigun's barrels go, on the same ramp —
           and when the stream moves on it cools over six seconds and
           leaves a SCORCH, a dark blot the size of the glow, for good.
           Additive, its own light.
  FROST    SPOT COOLING for the extinguisher: where the jet lands, the
           surface rimes over, whiter the longer the jet stays, and
           thaws over ten seconds when it moves on. It leaves nothing.

A landing within twenty-six units of a spot of its own kind feeds that
spot rather than starting another, which is what makes a held stream a
spot that HEATS rather than a trail of separate glows. AND THE TWO
ARGUE: gas landing within forty-four units of a hot spot takes a tenth
of the heat out of it, and flame landing that near rime melts a tenth
of it, so the extinguisher cools a glowing wall and the flamethrower
clears the frost off one — the same pair of verbs the two weapons
already have for people and for fires, on the shop itself.

EACH KIND IS ONE DRAW CALL, a pool of quads in one geometry: positions
written when a decal is placed, an intensity written every tic as it
cools or thaws, and a slot that has faded to nothing is free again. A
decal sits a hair off its surface along the surface's normal and is
drawn with a polygon offset, which between them keep it from fighting
the wall for the pixel; the normal is the wall's own line turned to
face the side the shot came from, or up for a floor, or down for a
ceiling, and the quad is laid across it. Holes and frost take the
wall's own light and fog, so a hole in a dark corner is not a black
square glowing in it; heat ignores both.


THE VANS UNDER FIRE
-------------------

A VEHICLE TAKES A LOT OF THE MINIGUN, at the user's request, and shows
every hit. The minigun does twenty-four to forty-eight a round and a
car has a hundred and fifty of health, so a hatchback used to be gone
in a tic and a half; what a round does to a vehicle is now divided by
its SHOT ARMOUR — twenty for a car in the lot, which is eighty-odd
rounds, fifty for the police van, ninety for the APC — and when the
health does go the vehicle chars and goes up exactly the way a burnt
one does, rather than vanishing. The holes go on regardless: a round
into a van leaves a hole on whichever face of the van's box it came
in through, at the point it crossed, and the hole RIDES WITH THE VAN
— it is kept in the van's own frame, x along, y across, z up off the
body, and turned into the world every frame — until the van stops
being a van, when it is dropped, because a wreck on its roof is not
the box the holes were laid on. See Decals.vehicleHole.

AND THE STREAM LIGHTS A VAN AND THAT IS ALL IT DOES, at the user's
request. The flamethrower's particles used to land on the blockers as
damage, six a tic at five to nine each, and a held stream took a car
apart in a couple of seconds without it ever really burning. A car
the flame reaches now CATCHES — ignite(), the same thing a blast or a
burning neighbour does to it — and burns on its own clock: forty
seconds alight, twelve off its health every ten tics through its fire
armour, the char, the launch. Holding the stream on it longer changes
nothing. A blast still hurts, because a blast carries `fire` and the
stream carries `stream`, and Vehicle.damage reads the second first.

AND THE ROUNDS ARE SEEN: every other one is a TRACER, a streak of
light four hundred and twenty units long — VERY long, at the user's
request — drawn from the muzzle to wherever the round stopped
(Game.lastHit, which every hitscan leaves behind), flying at a hundred
and fifty units a tic. It starts at the end of the barrel: the tail is
held at the muzzle until the head is a whole length out, so the streak
grows out of the gun rather than appearing in front of it, and once
the head has arrived the tail keeps flying and the streak shrinks into
the hit and is gone. A streak is
a quad that faces you along its length — spread sideways along the
direction across both the streak and the line to the eye, so it is a
line of light from wherever you stand and never a sliver seen edge-on
— bright white at the head, orange at the tail, additive, one draw
call for the lot. js/tracers.js.


THE JUMP, AND BEING HIT BY A VAN
--------------------------------

THE PLAYER CAN JUMP, at the user's request, which is the end of the
line at the top of js/player.js that said NO GRAVITY, NO JUMPING — and
it is done the way a Doom port does it rather than a physics engine:
a vertical momentum, a gravity of a unit a tic off it, and a floor
that stops it. Nine units of push is forty of height, enough to clear
a shelf end or a bonnet and not a gondola. A step up or down within
twenty-four is still instant, like Doom; a drop deeper than a step is
a FALL now, on the same gravity, which is what makes a jump off the
loading dock feel like one; a hard landing dips the eye by a share of
the speed it arrived at and the view's own smoothing brings it back.
The ceiling stops a jump the way the floor stops a fall. Space, L2 or
the JUMP button, one jump per press — holding it is not a pogo stick.

AND A VEHICLE THROWS YOU, at the user's request, instead of the six
units of sideways shove a hit used to be. SwatVan.runOver (the APC
inherits it) works a velocity out of how fast it was going — along its
heading blended with the line from its nose to you, so a square hit
throws you down the road and a glancing one throws you off it — and
UP, in proportion, so a van at speed puts you in the air and the
gravity above brings you down somewhere else. Player.damage spends it
(opts.launch), and thirty tics of grace on the player stop the same
nose finding you again every tic while you are still in front of it,
which is what it used to do at a shove's worth of push: the hit is one
hit now, at forty, rather than twenty-eight every tic for as long as
you overlapped. DEBUG: INVINCIBLE still refuses the whole function,
launch included, which is the documented reading of the word.


THE PAUSE MENU
--------------

FOUR PAGES OF TILES, at the user's request, and nothing in it scrolls.
It was one column of small words with a scrollbar down the side, which
is the wrong shape for the machine this is mostly played on: a phone
held sideways is a WIDE, SHORT window, and a long column in one is empty
down both sides and cut off at the bottom — and a list you drag with the
thumb that is meant to be pressing the thing you want is a list you lose
your place in.

So every option is a SQUARE TILE with rounded corners, three across and
two down, and each one says three things: what it is, what it is set to,
and where that sits among what it could be — a dot per stop for a list,
a bar for a number. Tapping it does one of two things:

  A LIST      cycles to the next value and wraps round. Three or four
              stops is short enough to walk round, and a switch is a
              list of two: CROWD, EFFECTS, THE WOOD, WEATHER, PIXEL
              ASPECT, and the toggles
  A NUMBER    opens A WINDOW with one slider in it, a nudge either side
              of the slider for the step a thumb cannot hit, and the
              value under: LOOK SPEED, MUSIC, BRIGHTNESS, CONTRAST,
              GAMMA, and the two ladders below

AND THE PAGES ARE TABBED — 1 CONTROLS, 2 PICTURE, 3 WORLD, 4 DEBUG —
which is what replaced the scrollbar: if a page is full the next one is
a tab away. The tiles are the same size and the page the same height on
every one of them, so the tabs and the two words underneath stay where
they are and the only thing a tab changes is what is under your thumb.
On a keyboard the arrows turn the page, or move the slider while a
window is open; escape shuts the WINDOW rather than the menu, so one
escape closes the window and the next unpauses.

RENDER and PIXELS are windows rather than tiles you cycle for the reason
the steppers existed: nine rungs is too many to walk round to go back
one. The slider walks the rungs, the two nudges are the old minus and
plus, and the readout in the window prints both actual sizes — 720P
1280x720 — because "400P" says nothing about how wide it is and the
width is where the pixels are. The tile has room for the setting and not
for the proof of it.

What the page holds and what the code reaches for are two files apart,
so the smoke test holds them against each other: every tile either names
a control js/main.js knows or opens a window that is there, every page
has a tab and every tab a page, and there is no scroller anywhere in the
menu's CSS. A tile that lights up under the thumb and does nothing at
all is the one thing this layout can quietly become.

AND YOU CAN READ IT, at the user's request, which the tiles on their own
did not settle. The layout was right and the paint was wrong: the game
behind the menu was shaded by 58% and no more, so every word in it was
read against whatever happened to be back there — a lit ceiling, a
burning car park, the gun — and moved when that did. The tiles were dark
glass at 78% with a hairline round them at 20% of a grey, which over a
bright frame is not an edge; the names on them were a grey at 55%; and
RESUME and RESTART, the only two things in the whole menu that DO
anything, were drawn as words with an underline that appeared under the
mouse. On a phone there is no mouse to find it with.

So the contrast is spent where it is worth something — at the edges:

  THE GAME GOES OUT       88% of shade, not 58%. The picture behind the
                          menu is a suggestion of where you were
  THE MENU IS A CARD      an opaque panel with a 2px rim and a shadow
                          under it, so there is one boundary between the
                          menu and the game instead of six faint ones
  THE TILES HAVE FACES    opaque, and a shade LIGHTER than the card they
                          stand on, with a 2px border: six things on a
                          surface rather than six darker patches of shop
                          floor
  THE TAB YOU ARE ON      is filled in, black on amber. A tint of yellow
                          at 8% is a difference you have to go looking
                          for, and which page you are on is the one
                          thing here to be answered across the room
  AND THEY ARE BUTTONS    RESUME filled, RESTART outlined, DOWNLOAD
                          outlined — three boxes with borders, at the
                          user's request. RESTART still asks twice, and
                          turns the colour of what it is about to do

Every one of those is a number in css/style.css, so every one of them is
checked: the scrim's alpha, the border widths on a tile, a tab and a
button, that the menu has a background colour of its own, and that no
text in it is written in a half-transparent grey.


TAKING IT HOME: THE DOWNLOAD
----------------------------

A BUTTON IN THE PAUSE MENU THAT HANDS YOU THE WHOLE GAME, at the user's
request: one zip file, to keep and to run on your own machine with
nothing to install and no network once it is unpacked.

There is no server here to ask for one. The game is a static page, and
the only machine in the transaction is the one already holding every
file — it fetched them all to play. So the page BUILDS THE ARCHIVE
ITSELF (js/pack.js): it reads the packing list, fetches each file back,
and writes a ZIP by hand. The fetches come out of the browser's cache,
which is why sixty megabytes takes about three seconds rather than a
second download of the site.

THE ZIP IS STORED, NOT DEFLATED. Fifty-six of the sixty megabytes are
PNGs, MP3s and GLBs, all compressed already; squeezing the two and a
half megabytes of source on top would cost a pass over everything to
save under two per cent. Every entry goes in flat, which makes the
writer small enough to read in one sitting: a local header and the bytes
per file, a central directory at the end, and a CRC32 of each. The
button is the progress bar — PACKING 0%, then SAVED 59MB — because
there is nowhere else in that menu to put one and a percentage in the
thing you just pressed is where you are already looking.

THE PACKING LIST is the one part that is not obvious. A page cannot ask
a static host what is on it, so the site carries a list of itself:
tools/build-site.sh writes files.json out of what it actually copied.
A list is a second copy of the truth and second copies drift, so the
same list is kept at the top of the repository — which is what makes a
checkout served straight off the disk pack too — and the smoke test
rebuilds the site and fails if the two are not the same file. An asset
added without regenerating it fails there rather than in somebody's
download.

AND THE ARCHIVE SAYS HOW TO RUN IT. Everything here is an ES module, and
a browser will not load one over file:// — it treats a page opened by
double-clicking as having no origin and blocks its own files, with an
error about CORS that tells you nothing about what to do. So the zip
carries RUN-ME.txt next to the page with the answer in it: serve the
folder with any web server and open localhost.

    python3 -m http.server 8000      # or npx http-server, or php -S
    http://localhost:8000/

The zip writer is written here and read back in the smoke test by a
reader that knows nothing about it — the table at the end is walked,
every name is found at the offset it claims, and every CRC is recomputed
off the bytes that came back. A writer that puts one byte in the wrong
place makes a file every unzipper refuses, and nobody finds that out
until somebody tries to keep the game.


BRIGHTNESS, CONTRAST, GAMMA
---------------------------

THREE SLIDERS IN THE PAUSE MENU, at the user's request, and they are
applied in the one place in the pipeline where they are honest: after
the block average and BEFORE the dither and the palette snap. Doom's
own gamma keys worked that way — they changed the palette the picture
was quantised to, not the picture after — and the reason still holds:
a brighter picture should still be made of the same two hundred and
fifty-six colours, and a lift applied after the snap puts colours on
the screen the palette does not have. Contrast pivots on mid grey,
brightness multiplies, gamma is the usual curve, and 1 on all three is
the picture as drawn. THE DEFAULT BRIGHTNESS IS 1.35, at the user's
request — the picture a third brighter than drawn — and the other two
sit at 1. They are remembered with the rest.

AND THE DEFAULT PICTURE IS 480P RENDERED, 240P OF PIXELS AT 2:3, at the
user's request and for the frame rate. It was 960 and 320, which is the
finest buffer this game has ever drawn and FOUR TIMES the shading of
this one: a phone was paying for rows that the grid in front of them
averaged away again. The 3D really is 480 — the render buffer measures
853 by 480 on a 16:9 window, which is what the fragment shader is
actually run over, and the grid in front of it is 640 by 240. Two buffer
rows to every chunky row exactly.

The finest rungs are still on both ladders for anyone with a machine
that wants them: 960 at the top of the render ladder, 320 still on the
pixel one. It was 720 and 240 at 5:6 before all this, and 200 before
that. The pixel aspect ladder has five rungs — SQUARE, TALL 5:6,
TALL 2:3, WIDE 7:6 and TALL 1:3 — and the default is still 2:3, a pixel
half again as tall as it is wide. A saved setting from before takes the
new defaults, as every moved default has.


ON A PHONE
----------

The phone is the main way this is meant to be played, so the controls
were designed rather than bolted on. Open the page, tap, and:

  LEFT THUMB    a stick appears where the thumb lands. Push a little
                to walk, all the way to run; the knob goes yellow at a
                run. Pull past the rim and the stick is towed along
                behind the thumb, so a long drag in a new direction
                changes direction instead of pinning you against the
                old rim.
  RIGHT THUMB   drag anywhere to look. The view moves exactly as far
                as the thumb did and stops when it stops.
  FIRE          under the right thumb's rest, and it says FIRE now
                rather than wearing a flame, at the user's request —
                with a minigun in the game a flame was a lie a quarter
                of the time. Hold it — and while it is held, sliding
                the same thumb still looks, so a held flame swept
                across an aisle is one motion. That one detail is what
                makes a one-weapon game playable with two thumbs: the
                thumb that fires never lets go to aim.
  JUMP USE SWAP the three small buttons, in an arc round the big one:
                jump at nine o'clock, use at half past ten, swap at
                twelve, all the same distance from FIRE's centre, so
                the thumb rolls from one to the next without leaving
                its corner and the big one is always nearest. JUMP is
                the newest, at the user's request, and took the spot
                beside FIRE because jumping and firing are the two
                things you do without looking.
  AIM  2.1x     the scope, for the two guns that have one — the lance
                and the quad launcher — and only while one of them is
                in hand, on a second arc outside the first, each in the
                notch between two of the three. AIM, at the user's
                request, puts the gun up to your eye and takes it down,
                and is lit while it is up. The magnification shows only
                while it is up, with its step written on it, and steps
                between the aimed steps without ever dropping the gun to
                the hip; up again after AIM has taken it down is the
                step you left it on.
  PAUSE         top corner. Four tabbed pages of square tiles, which
                is a layout that fits a window this shape — look speed,
                invert, a left-handed mirror of the whole layout,
                vibration, brightness, contrast and gamma, chunkiness
                and fullscreen — and it remembers all of it. Nothing in
                it scrolls; see THE PAUSE MENU.

AND A PAD TAKES THEM OFF THE PICTURE, at the user's request. A phone
with a controller paired is still a phone — no keyboard, menus you tap
— but while the pad is being used the thumb controls are in the way of
nothing but the view, so the moment a stick moves or a button goes
down they fade, in a quarter of a second, and the moment a finger
touches the screen they are back as fast. input.js decides
(Input.padHeld, true from the first button until the next touch);
touch.js only wears the class. The weapon's name in the top right
steps left past the pause button on a phone, for the same reason the
old status bar's height used to be handed to the CSS: the two corners
are shared and somebody has to give way.

The rules the layout follows: nothing ever sits over the picture's
status bar, whatever the chunkiness (the bar's height on screen is
handed to the CSS every resize); every target is at least a thumb wide;
the controls dim after a couple of seconds untouched and brighten under
a thumb; the frame and the controls both keep inside the notch and the
home indicator; the first-time MOVE and DRAG TO LOOK hints go away the
moment each is used. A finger the browser takes back — an edge swipe, a
notification — releases whatever it was holding, so a stick is never
left pushed. Dying or getting out drops the controls, and after a
moment's grace any touch goes again.

The page asks for fullscreen and landscape on the start tap where the
browser allows it (Android); on an iPhone neither is allowed from a
page, and adding it to the home screen — the manifest and the icon are
for that — opens it without the browser around it. Held upright it
still plays, but a first-person view through a keyhole is not the game,
and it says so at the top of the screen.

Which kind of machine it is gets decided by whatever spoke last: a
laptop with a touchscreen is a phone until a key goes down, a phone
with a keyboard is a desktop until it is tapped. The game never finds
out — it reads one Input, and touch.js writes into it like any other
device. Pointer lock is a desktop-only idea and is never asked for by
touch.

One thing came out of building this that had nothing to do with
phones: the pause was a one-way door. update() returned before the tic
that sampled the pause key, so nothing could ever unpause, and on the
desktop Escape drops the pointer lock and the browser swallows the key
anyway. Now a lost pointer lock is a pause, the menu releases the mouse
so it can be pointed at, and a hidden tab pauses too.

AND START OPENS IT, at the user's request, which it did not. Pausing was
Escape or P and nothing else — so a player on a pad had no way into the
menu at all, and the button that had been sitting in the corner of the
page for a player on a phone since these controls were built was wired
to nothing on the way in. .tb-pause was in index.html, styled, mirrored
for the left-handed layout, and js/touch.js simply had no branch for its
kind: tapping it did nothing. Both now raise the one flag Game.update
reads, on both sides of the pause.

BOTH OF THE PAD'S MIDDLE BUTTONS, not just the one: nine is Start in the
standard mapping and eight is Select — Options and Share, Menu and View,
plus and minus — and which of the two a player reaches for is a matter
of what console they grew up with. Neither does anything else here.

AND EVERY PAD EDGE IS NOW TAKEN BEFORE THE OR, which two of them were
not. padEdge has a side effect — it records what the button was doing
this frame — so an || that short-circuits past it leaves that record a
frame stale and swallows the NEXT press off the pad. Pressing Z while
resting a thumb on B was enough to do it, and jumping had the same
shape. Sampled into a local first, every time.

AND THE SCOPE HAD A BUTTON THAT NEVER SHOWED. It went in with the lance,
styled and placed, and TouchControls.setScope changed its `hidden` only
when it was already what it was being changed to — so from the day it
was written it sat hidden in the page, and on a phone there was no way
to raise a scope at all. Which is what the user found, and asked for a
button for. It was also placed a third of the way past SWAP and a little
above it, which on a phone is half on top of SWAP, and its thumb never
came off it — nothing released a held 'zoom'. Nobody saw any of that,
because nobody saw the button. AIM and the magnification replace it,
the suite lays the arc out off the style sheet at the smallest, a
phone's and the largest size the fire button comes in and checks that
nothing is on top of anything, and
setScope is checked on a stand-in page for showing what it says it
shows.

AND A PRESS OF THE SCOPE IS KEPT UNTIL IT IS TAKEN. The input is sampled
once a tic, thirty-five times a second, and the scope is worked once a
FRAME, and the two are not the same clock: at sixty frames a second four
frames in ten have no tic in them, and the flag the zoom read was simply
left standing between samples — so one press of Z stepped the scope
twice about as often as that, and a toggle would have gone up and
straight back down, which is a button that does nothing. The presses
are latched now, and taken exactly once by the frame (Input.takeScope),
whatever is in hand, so a press made holding something else is not
waiting to go off when the scope comes out.


THE PARADE
----------

TWENTY IN-LINE UNITS, ten each side, and three of them have a name. It was
six, three each side, and fourteen more went in at the user's request.
That is a different building: the frontage was six and a half thousand
units long and is nearly thirteen now, about three hundred and seventy
metres, and it changes what the place IS. Six units either side of a
superstore is a shopping parade with an anchor on it. Twenty is a STRIP
MALL, and the difference is that the anchor stops being most of what you
can see — from the mouth of the car park the building runs off both edges
of the screen and the store is the lit part in the middle of it.

THREE NAMES ARE LEFT ON THE BUILDING and they are the three units that
still have a tenant in them: the chemist, the kebab shop and the phone
shop. There were four. The laundrette's WASH board came off when every
shut unit's sign went dead, because the laundrette is shut, which makes
it an empty store, and a maintained sign over three years of roller
shutter is the exact thing that change was asked to stop. It keeps its
name in the map — a laundrette that closed is still a laundrette, and
that is what the sector is called and what the fire reports — it just
has nothing over the door any more.

THE FOURTEEN ARE UNBRANDED, which is what was asked for and is also the
only honest way to draw fourteen more. A fascia is one repeat of a
96-tall texture and a 432-wide unit says its name seven times, so
eighteen NAMES along that elevation is a hundred and twenty-six legible
words shouting over the one sign the level is about. Four is a parade
with character. Eighteen is noise. So the new ones carry the TRAY and the
paint in it and nothing else — six colours, muted, because a row of
saturated boards reads as bunting — and what tells one from the next is
what tells one unnamed unit from the next in a real parade: whether the
lights are on or the roller is down.

AND THE RULE IS VISIBLE FROM THE CAR PARK: if the lights are on, the door
works. Seven of the twenty are open now, up from two, each with a run of
shelving down both sides, a counter with a flap in it and a back room.

THE OTHER THIRTEEN ARE METAL. There used to be a third state — glass
whitewashed from the inside — and it went, at the user's request to make
the empty ones read as empty, because it was the wrong answer to the
question this parade is asking. Whitewash says somebody is FITTING OUT:
it is what a landlord does to a unit that is between tenants and about to
have another one. A roller left down for three years says nobody is
coming, and that is the state this place is in.

So an empty unit is shut, and there are two shutters rather than one
because thirteen in a row out of a single texture is a hundred and thirty
metres of wallpaper. One is mill-finish aluminium: the crowns of the laths
worn bright where a decade of weather and hands and trolleys has been at
them, the rust in the JOINTS where the water sits, a few dents with a
bright lip on the top edge, and the ghost of a tag somebody scrubbed —
which is better than a fresh one, because a shutter covered in bright
paint is a shutter somebody still visits. The other was painted blue and
has chalked: the colour gone flat and pale, the paint letting go in a
handful of hard-edged patches rather than everywhere at once, and more
rust through the holes.

AND THE SIGN SAYS THE SAME THING THE GLASS DOES, which it did not before.
Every unnamed unit carried a painted tray in one of six colours whether
the lights were on or not, and the board is the bigger surface of the two:
from the car park you read the fascia before you read the shopfront. A
closed one now gets a DEAD board — chalked to almost nothing, stained
under both its fixings, with the clean band across it where the sign panel
was bolted before somebody unbolted it. Three of those, for the same
reason there are two shutters.

THE DEAD BOARDS ARE PALER THAN THE LIVE ONES, not darker, and it took a
screenshot to see why that matters. They were first painted at the same
tone as the live trays, and at the 0.46 the footway lights a shut unit
with, a dark green board and a dark blue one both came out very nearly
black — which reads as an unlit sign and not as an abandoned one. A dead
board is not unlit. It is CHALKED, which is the binder going and the white
filler coming out, so the failure state of paint is pale.

AND THE ROLLER REACHES THE GROUND, which is one free box per shut unit.
The curtain of a shutter is the same thing all the way up, and that is
exactly what lets its texture tile four times cleanly over a 220-tall
shopfront — so the texture cannot contain the one part of a shutter that
happens ONCE. Without a bottom rail the metal runs off the bottom of the
wall and reads as a metal WALL; with one, it reads as a curtain somebody
pulled DOWN. Same argument as the coping, one storey lower.

THE CAR PARK HAD TO GROW WITH IT, because the wood down each flank of the
building is the strip between the lot's edge and the end of the parade —
a parade longer than its own car park is a rectangle with a negative
width and a map that will not build. So the lot is derived from the
parade now instead of being two typed numbers, and the parking thins in
two directions rather than one: people park near the DOORS, so the
chance of a bay being taken falls off with distance from the entrance as
well as with distance from the road. A lot this wide with cars only in
the middle of it is the cheapest frame in the game for how much of this
place is already over.


WHAT A STRIP MALL HAS THAT A SHED DOES NOT
------------------------------------------

The town got this pass first and the diagnosis out here turned out to be
the same one. A building drawn out of sectors is a building drawn out of
CEILING HEIGHTS, and a sector engine cannot put anything proud of a wall
or above a roof — so what the parade was, for a long time, was four
horizontal bands stacked up and running thirteen thousand units off both
edges of the screen. Not badly textured. Just FLAT, in the way a
cardboard model is flat: no coping, no gutter, no downpipes, no
pilasters, and nothing at all on the roof.

The fix is the one the town uses: FREE BOXES. Six faces owned by no
region, batched into the block they stand in, drawn by `boxGeometry` in
js/mapgeo.js. There are about two hundred and forty of them on the parade
now and every one is a piece of the same argument.

THE COPING, first, because it is the silhouette. A parapet drawn as a
step in a ceiling just STOPS: a cut edge with sky over it, which is the
loudest thing wrong with a shed built this way and the thing you notice
from the far end of the car park without being able to say what it is.
There is a pressed aluminium capping on it now, twelve units out over the
lot and eighteen tall, one length per tenancy so the batcher gets a box
per block rather than one box thirteen thousand long.

WHICH MADE A TEXTURE WRONG. T.PARAPET had a coping PAINTED INTO IT —
lighter rows at the top with an open joint — and that texture is thirty-two
tall on a band of a hundred and fifty-two, so the painted coping repeated
nearly five times and the roofline read as five cornices stacked up. A
coping happens ONCE. It is a box now and the wall under it is one
material all the way up: render on blockwork, a control joint at the
repeat, thirty years of rain. The test of a texture that tiles five times
vertically is whether you can count the repeats, and you should not be
able to.

THE PIERS, second, because they are the only vertical rhythm a
thirteen-thousand-unit elevation has. A pier was a sixteen-wide change of
texture in a flat wall, which from a car park is a STRIPE. What a pier is
is a pilaster: a column of brick standing eight units proud of the face,
running from the tarmac to above the parapet, with a cast cap on it that
breaks the line of the coping. Both of those are shadows, and the shadows
are the whole of it. Twenty-two of them, one per joint plus one at each
end, each carrying the downpipe that takes the water off the canopy
gutter — which is another thing that was not there, and water has to go
somewhere.

THAT MADE A SECOND TEXTURE WRONG, in the other direction. T.PILASTER's
brick was courses of eight and bricks of thirty-two over a sixty-four
unit repeat, which at thirty-two units to the metre is a brick a metre
long and a foot tall. Fine as a distant stripe. Absurd once the thing
stands proud enough to walk up to, which is what a pilaster does. It is
the town's brick now — sixteen by six, the same `brickwork` call the
chimneys use — so a pier and a chimney are made of the same material,
which is the only reason a generated texture set holds together at all.
T.STORBASE had the identical fault and got the identical fix.

THE FASCIA IS A TRAY. The sign band was paint on the face of a wall, and
a painted band is a painted band however good the texture is. Two rims,
eight units proud, one along the top edge and one along the bottom — and
the same paint is now a box screwed to a building, which is what every
fascia on every parade in the world actually is.

AND THE ROOF, which is the silhouette of the building TYPE. A supermarket
is a windowless box and the only reason anybody can stand up in one is
the plant on top of it; every strip mall in America has three or four
packaged air conditioners showing over a parapet that was built to hide
them and doesn't. There are twenty up there now — one on most of the
in-line units, five bigger ones in a line across the anchor with ducting
between them, because they serve one tenancy and went in on one day. Set
back ninety-six units so the coping crops the bottom of each, which is
what makes them read as standing on a roof rather than as boxes glued to
a wall.

AND A WAY UP TO THEM. There is a caged ladder on the back wall in the
service yard, running the full height. It is there because the roof plant
asks the question and nothing in the level had an answer to it.

THE SHOPFRONTS get the housing every roller winds into and a light over
every door — and THE LIGHT IS THE TENANCY. The parade already told you
who was left by whether the glass was lit or the roller was down; the
fittings tell you now too, because a wall pack at full brightness says
somebody pays that bill and a dead one says nobody has for years. Same
rule, one more surface saying it — and the fascia is a third, since a
closed unit's board went dead as well. See THE PARADE.

AND THE CAR PARK, which had no object in it taller than a van and
therefore no scale at all. Lot lighting on the strip where two rows of
bays meet nose to nose — the one strip of a lot nobody parks on, and
where every lot light in America stands — every four bays, using the same
STREETLAMP cutout the town's streets use. Precast wheel stops, one per
bay, on the three rows nearest the doors. And two trolley bays, each
taking one bay out of a back-to-back pair, which is where a real one goes
and how big it is.

THE TROLLEY BAY IS A FENCE AND NOT A BOX, and that distinction is the one
decision in this pass worth arguing about. A free box does not collide. A
rail you can walk through is not a rail, it is a picture of one — so the
corral is a REGION with its own hatched floor and the galvanised tube
hangs in the lines round it as a middle texture, exactly the way the
yard's chain link and the town's picket fences do. T.TROLLRAI had been
painted and sitting unused in js/textures.js since the car park was
built. This is what it was for.

THE SAME ARGUMENT SENT THE SKIPS BACK. They were free boxes for about an
hour, and a steel skip the size of a car standing in a yard you walk into
through a roller shutter is not a thing you get to walk through: that is
not a detail, it is a bug you can find in ten seconds. The skips and the
eight condensing sets behind the store are RAISED FLOORS now, exactly the
way the town's boxwood hedges are — a region whose floor is the top of
the thing and whose lowerTex is the thing's own skin, which the
disagreement rule then draws down all four sides. A hundred and twenty-eight
is five times MAX_STEP, so a skip is solid.

WHICH LEAVES ONE EXCEPTION AND IT IS DELIBERATE. The wheel stops are free
boxes standing on the ground, and they are the first thing in this game
that is neither above your head nor flat against a wall. They get away
with it because they are TWELVE tall against a MAX_STEP of twenty-four,
so walking through one and stepping over one are the same move. The smoke
test holds them to that number.

Fifteen new textures for all of it, every one at sixty-four pixels or
under like everything else here, and every one declared at the size of
the thing it is a picture of — so one repeat is one length of coping, one
luminaire, one wheel stop, one cabinet. Get that wrong and a wall pack
becomes wallpaper of wall packs, which is the mistake the agent's board
on the vacant unit was and the mistake the painted coping was, twice over.

ONE THING IN THE GEOMETRY BUILDER CHANGED to make any of it work: a free
box can have an UNDERSIDE now. A box with no floor is invisible from
below — every side is wound outward and there is nothing at the bottom —
which is fine for a chimney and wrong for the three things in this game
you stand directly beneath: a porch roof, a shop awning and the canopy
over a fire exit. All three had that hole in them and all three are shut.


A SHOP WINDOW IN SIX LAYERS
---------------------------

At the user's request, and it is the biggest single change the front of
this building has had. A shop window was ONE QUAD: a texture with
mullions, a transom and a stall riser painted on it, hung flat on the
front of the wall. From the far side of the car park that reads; from the
footway it reads as a picture of a window taped to a wall, because the
one thing glass does that nothing else does — hold a reflection on a
surface that is IN FRONT OF what you are looking at — needs two surfaces
and it only had one.

A shopfront, counted from the pavement inwards, is six things:

  the FRAME               aluminium, standing proud of the wall
  an INSET                the reveal behind it
  PANE A                  the outer sheet, with the sky on it
  a GAP, outlined black   the cavity between the sheets
  PANE B                  the inner sheet
  an INSET                and the shop behind that

All six are built. The sixteen units of wall thickness — the void
between two rooms, the one rule the whole map keeps — turns out to be
exactly enough room for the last four of them:

  y  -25   the frame, as free boxes: cill, head and a mullion each side
  y  -16   PANE A, a middle texture in the hole
  y  -10   PANE B, a middle texture in the next hole
  y   -4   the back of the reveal, painted with what is inside
  y    0   the shop floor

The two cavities are a pair of six-deep sectors cut into the wall, and
the panes hang in the holes between them the same way the yard's chain
link, the town's pickets and the church's stained glass hang in theirs.
The cavity between the sheets is skinned near-black on all four sides at
once — two jambs, a floor and a lid — and that black outline is the line
that makes a sheet of glass an object instead of a gap. What it buys
over a painted window is PARALLAX: walk along the footway and the gloss
on the outer sheet slides across the gloss on the inner one, and that
sliding is the only thing in a game that ever says glass.

SEMI-TRANSPARENT MEANS STIPPLED, AND THAT IS NOT A COMPROMISE. Nothing
in this game has partial alpha. snapImageData in js/palette.js sets every
surviving pixel to 255 and says "no partial alpha, ever" in a comment
while it does it, and a wall material here is alpha-TESTED, never
blended. So a half-silvered pane is drawn the way a half-silvered pane
was drawn in 1996: an ordered dither of pixels that are there and pixels
that are not, off the same 4x4 Bayer matrix the palette snap uses,
applied to alpha instead of to colour.

WHICH MEANS THE MIPMAPS ARE THE DESIGN. A fifty-per-cent checker averages
to fifty per cent one mip level down, and an alpha test at 0.5 turns that
into all or nothing — a pane that vanishes at ten metres or one that goes
solid. So the veil is DENSER AT THE EDGES OF THE PANE THAN IN THE MIDDLE.
Stand at it and the middle is a third there and you look through it;
walk away and the mip chain averages the alpha, the border firms up into
solid glass and the middle opens out. Which is the right way round: from
the far side of a car park a shopfront IS a sheet of reflection, and the
pane you can see through is the one you are standing at.

THE GLOSS IS ARTIFICIAL ON PURPOSE. A real reflection in a shopfront is
the car park, and nobody has ever drawn the car park on a window. What
everybody draws is two hard parallel bands raked across it from the top
left — which is also where the light in every texture in this project
comes from — and that is what these are. The outer sheet's bands and the
inner sheet's are shifted against each other, because two sheets whose
gloss agreed would read as one sheet with a bright line on it.

THE REVEAL STOPS FOUR UNITS SHORT OF THE SHOP FLOOR, and that sliver of
wall is the whole reason this is affordable. Let it reach and the front
of the anchor becomes a three-thousand-unit PORTAL: the visibility flood
opens the entire shop floor to anybody standing in the car park, and the
interior LOD — which exists precisely so a supermarket is not drawn from
outside it — has nothing left to do. So the back of a reveal is a
one-sided wall with a PAINTED interior on it, out of focus because it is
behind two sheets of glass, and there are three of them: the anchor's
lit aisles and strip lights, a small unit's shelf run and counter, and
the near-black of a unit whose roller is up and whose lights are off.
That third one is a state this parade did not have — somebody still holds
the lease — and the phone shop is in it.

ONE PANE IS ONE REPEAT, which is the rule everything on this building
keeps. The module is 96 by 160 and it is not negotiable; the leftover in
a run goes into the MULLIONS, which are an aluminium extrusion and may be
any width at all. Do it the other way round — panes sized to fit, a fixed
mullion — and every run on the parade has a different fraction of a sheet
of glass in it. The pane's left edge snaps to the unit as well, so a
1708-wide run comes out as fourteen sheets of exactly 96 and mullions
that differ from each other by a unit, which is a thing nobody has ever
noticed about a shopfront.

Forty-six panes: twenty-nine across the anchor in three runs, two in each
of the seven small units that still trade, three across the phone shop.
A hundred sections of frame. Seven new textures. The cost, measured
against the same four viewpoints before and after, is nineteen draw calls
at the mouth of the car park, twelve in the middle of it, five on the
footway and none at all from the town.


THE LAST DOOR THAT WENT UP
--------------------------

Doom had exactly one door: a ceiling that goes up. The shopfront's
sliders and the six fire exits have never been that — they are quads on
a transform, because a rising portcullis at the front of a SellWrong
would be the first thing anyone noticed — but the STAFF ONLY door at the
back of the shop floor still was, and it was the worst thing in the
building.

A shut Doom door is a sector whose ceiling has come down onto its own
floor. The disagreement rule then has nothing to stop it: it draws the
face of that door from the floor all the way up to whatever the ROOM's
ceiling is, which back there is 352 on the shop side and 416 on the
stock side. The door texture had no declared size either, so it repeated
every 64 units. What you actually walked up to was a black slab five
storeys high with TEN "STAFF ONLY" signs tiled up it, every one of them
sliced through the word by a seam.

Nothing was wrong with the picture. It was on the wrong kind of surface.

So the staff door is built the way the other two doors in the building
are built, and there is now nothing left in this map that rises:

  the OPENING             a sector 128 by 116 in the thickness of the
                          wall, and its ceiling IS the head
  the TRANSOM PANEL       the band from the head to the ceiling. A band
                          is drawn once for BOTH of its faces, and this
                          one has a panelled olive shop floor on one side
                          and a brick stockroom on the other — so it is
                          neither of them. It is the doorset's own panel,
                          in the same painted steel as the frame, which
                          is right from both rooms because that is a real
                          thing that really goes over a door of this kind
  the FRAME               pressed steel, six free boxes, proud of the
                          wall on both faces, and the same featureless
                          extrusion trick the shopfront's frame uses so
                          that it tiles round a corner
  the LEAVES              a PAIR of impact doors on hinges at the jambs,
                          swinging into the stockroom, with a stainless
                          kick plate where the roll cages hit them, a
                          push plate at shoulder height and a wired-glass
                          vision panel each
  the SIGN                a plate over the head, on the public side, and
                          the only place in this building where the words
                          STAFF ONLY are written down

A word is a shape you can count, and the moment it is on anything that
repeats you are reading it twenty-eight times. That is the rule the fire
exit's running man was drawn to keep, and it is exactly the rule the old
staff door broke. A sign never repeats, so the words moved onto one.

THE PAIR IS A FLAG AND NOT TWO DOORS. Two SlideDoors side by side share
the opening's lines, so each would overwrite the other's answer about
whether the door is wall this tic. Worse, the swing direction is not a
choice — it falls out of the order the opening is declared in, one jamb
to the other — so two leaves hinged at OPPOSITE jambs must be declared in
opposite orders and would always swing apart from each other, like a
saloon door being shoved from inside itself. A pair is therefore one door
with two leaves, the second turned through half a circle to hang off the
far jamb. Which pays for itself: the far leaf's u runs the other way in
the world, so ONE texture gives a mirrored pair, with the outer stiles at
the jambs and the two meeting stiles coming together in the middle.

WHO OPENS IT is the other half of what makes it a staff door rather than
a doorway. It takes the fire exit's rule and not the entrance's: the
player trips it at any hour, because the player goes everywhere, and the
crowd only trips it once it is running — which is the moment a STAFF ONLY
sign stops meaning anything at all.

AND A SHUT ONE IS NOT A WINDOW. A steel leaf blocks sight as well as
movement, which is a per-door flag and not a class one, because the
entrance is glass and the whole point of it is that you stand in the car
park and see the shop you are about to walk into. Without it the portal
flood went from the stockroom, through this doorway, down an aisle,
across the rear cross-aisle and out of a fire exit into nine thousand
units of wood — a forest drawn for somebody standing in a stockroom.

AND EVERY LEAF IN THE BUILDING WAS UPSIDE DOWN. Found by building this
one: a canvas texture is uploaded flipped, so v = 0 is the BOTTOM of the
picture, and the mapping anybody would write — the top of the leaf to
v = 0 — hangs it over. Six fire exits had been standing there with the
running man down by the threshold and the crash bar above it, and nobody
had noticed, because until this door there was nothing on a leaf with an
unmistakable right way up. A kick plate on the lintel is unmistakable.
One line of UVs fixes all nine doors, and the suite now reads the two
vertex attributes together and asks of every leaf in the game that the
vertex at the top of it carries v = 1.

AND THEN THE SAME DOORSET ON THE FIRE EXITS, at the user's request, and
augmented for what a fire exit is rather than copied onto it. Same reveal
lining, same soffit over your head as you come out, same transom panel,
same pressed frame proud of both faces, and the leaf repainted in the
same construction — pressed rib, stiles, three butt hinges down the side
it turns on, and a stainless kick plate. What it gets that the staff door
does not:

  a CRASH BAR and a running man, which it already had and which are the
    two things on a fire door that are not decoration
  the WEATHER, because this leaf faces nine thousand units of wood: rust
    runs from under the hinges and from under the bar
  a CANOPY, a light over it and the intake cabinet beside it, which it
    also already had — this is the face of a building and the staff
    door's is the face of a partition
  a LIT SIGN inside, over the head, on the side people are running from.
    The staff door's plate says who may go through it; this one says that
    you may

THE TRANSOM PANEL EARNS ITS PLACE HERE TWICE OVER. A band is drawn once
for both of its faces, and this one has a cross-aisle on the inside and
the wood on the outside — so whatever goes over the head was always going
to be wrong for one of them. It used to be the stockroom's blockwork,
which is a third thing that is neither: a strip of bare block up the
outside of a panelled flank and a strip of bare block over a papered
aisle. A panel that belongs to the DOORSET is right from both, and from
out in the wood it does something the old one did not, which is mark
where the exits are.

THE OLD EXIT SIGN HAD NEVER BEEN HUNG ANYWHERE. It was in the texture
bank and used by nothing, and hanging it explained why: dark green
lettering on a dark green field, which at the 0.26 of a cross-aisle at
night is a black rectangle over a black door. An illuminated exit sign is
the brightest small thing in a shop — it has a battery in it for the
night the power goes — so it is a bright face, white letters, a white
running man, and a box lit past one. Two of them are legible from the
middle of the shop floor.

AND A SHUT STEEL LEAF STOPS SIGHT, which turned up the oldest bug either
of these doors has found. Giving the fire exits the staff door's `opaque`
took the whole west side of the building away.

The portal flood decides what is drawn a BLOCK at a time, and it asks a
block whether any REGION in it is visible. A region is in the block its
middle lands in; a line is in the block its MIDPOINT lands in. Those are
usually the same block. The case where they are not is a big outdoor
region owning the wall of the building it wraps round — and the wood
behind the west wing is nine thousand units of forest whose middle is a
block and a half from the supermarket, while the supermarket's west flank
is the wood's own one-sided wall. Its triangles land, correctly, in the
anchor's block, whose visibility was answered entirely by the anchor's
aisles. So the outside of the building was drawn only because six shut
fire doors were leaking the flood into the shop. Shut them to sight and
the building lost its outside.

The fix is one line and moves nothing: a block is answered for by the
regions centred in it AND by the owners of the lines drawn in it. The
triangles stay where they are, so a block is still rebuilt on its own and
still culled by its own corner. It costs two to five draw calls outdoors
and saves thirty-four standing in an aisle, nineteen in the stockroom and
fourteen on the footway, because a cross-aisle no longer draws a forest
through a shut steel door.


ALL THE WAY DOWN
----------------

At the user's request, and it is the other end of the thing this game
already had. There was a fire that ate a building and left it standing.
Now there is one that brings it down.

A region used to have two states past "shop". CHARRED, at half its fuel,
which is a surface: the same aisle with everything in it blackened.
GUTTED, at ninety-two per cent, which is a structure: holes through the
walls with the studs behind them, a slab with ash on it, and no deck —
js/ruin.js hangs the steel the deck was sitting on, and what you look up
at in a burnt-out bay is a frame rather than a rectangular hole in the
world.

There is a third now. COLLAPSED, which is the absence of a structure:

  the ROOF          is not over the region, it is in it
  the WALLS         come down to a stub you can see over
  the FLOOR         comes UP, by less than a step, and is a heap
  and all of it     is still alight

THE THIRD STAGE NEEDED A CLOCK THE FIRST TWO DID NOT. Those two run off
how much of a region has burnt, and that number saturates at one and
stops — so as far as the old arithmetic was concerned, nothing further
could ever happen to a gutted region and a burnt-out shed stood for ever.
Steel does not care how much has burnt. It cares how LONG it has been
hot, which is the whole of a fire brigade's judgement about whether to go
into a building. So INTEGRITY is a clock: one when the frame is whole,
zero when it is on the floor, and falling for as long as there is fire AT
the region.

AT, AND NOT IN, WHICH IS THE TRICK. A gutted region has almost nothing
left to burn by definition, so a clock watching only its own cells would
run for the few seconds of its last eight per cent and stop. What cooks
the steel over aisle six is the fire in aisle five. So a burning cell
credits its own region AND every region it is LINKED to — through a wall
that is nothing, across an open aisle that is everything — and a bay only
comes down while the building around it is still going.

Two consequences, and they are the two worth having. A shop that burns
from end to end comes down, a bay at a time, in the order it burnt. And a
bay at the EDGE of a fire — one that gutted and then had the fire move
off it, or had the rain put it out — stands as a ruin, because nothing
kept cooking it. Which side of that line a bay falls on is not a coin
flip anywhere in the code; it is where the fire went. Burn the whole shop
and about seventy per cent of what gutted comes down and thirty per cent
of it is still standing in the morning.

THE FIRST CUT RE-FUELLED A GUTTED REGION instead, on the reasoning that a
burnt-out building is full of burning deck. It is, and it was still the
wrong mechanism: fuel put back above the threshold a cell needs to light
its neighbour means a ruin relights the room next door, which relights it
back, and the fire stops being something you set and becomes something
that cannot be stopped. The sign it was wrong was not in the fire at all.
It was the police, who could no longer keep a van in the car park long
enough to get out of it. A clock adds nothing to the world. That is the
point of a clock, and there is a check that says so.

WHAT YOU WATCH WHILE IT HAPPENS is the frame. Every number js/ruin.js
draws the steel from reads integrity now: how many joists have gone, how
far the rest have drooped, how much of the odd panel of deck is still
lying across a bay, and how brightly the whole thing is glowing. A bay
that is nearly down has lost half its joists and the rest are hanging
forty units lower than they were. It is quantised into four steps rather
than run continuously, because the frame is STATIC geometry and a
continuous number would have no picture attached to it until the moment
the bay fell — which is the exact moment the user asked to be able to
watch the run-up to.

AND THE HEAP IS THE SAME LATTICE, LYING DOWN. Everything the roof was is
still in the region, it is just on the floor: the joists that ran east to
west are lying east to west, broken where they folded, and the deck is in
sheets between them. Which is why it is not a pile of random boxes — it
is the frame above, drawn at ankle height, off the same hash of the same
lattice index, so two collapsed bays next to each other share a heap for
the same reason they shared a roof.

A HEAP IS A FLOOR THAT HAS RISEN and not a ceiling that has fallen, which
is the only way a sector engine can say the word. A ceiling on the floor
is a region you cannot be in; a floor that has come up is one you clamber
over. It rises by twenty against a MAX_STEP of twenty-four — the same
bargain the wheel stops in the car park make, because a heap you cannot
climb is a wall that would trap whatever was standing in the bay when it
came down — and what makes it read as more than twenty units is the pile
on top, which is low in the middle where you walk and banked against the
walls where you do not.

AND A COLLAPSE LEVELS A REGION TO WHAT IS AROUND IT. Most of this
building is not floor: a gondola run stands at eighty and a chiller at
forty, so raising every region by the same step made a run of collapsed
bays into a staircase of shelf tops. What a collapse does to a shelf run
is knock it over. A region comes down to the lowest thing still standing
beside it and the heap goes on that, which turns four fallen bays into
one continuous field of wreckage at one height.

AND YOU CAN BLOW IT UP. Fire is the patient way down and a blast is the
other one: `structure` on an explosion takes integrity off every region
it reaches, falling off with distance, and anything it takes past zero
goes through all three stages in the same tic. It is walked on the fire's
own grid, which already knows which region every point of the world is
in — so a blast reaches exactly as far as a fire does and stops at the
same walls. Three things in this game carry it:

  a can of accelerant    a sixth of a bay: a way to start something
  a car going up         a third, times the size of the bang, so the
                         chain reaction in the car park takes the
                         shopfront and the fire does the rest
  a VTOL coming down     one and a third, over five hundred and sixty
                         units, which flattens what it lands on

AND NOT EVERYTHING IS A BUILDING. Two of the three stages already ask
that question in one line — a region with no fuel cannot char and cannot
gut, which is how a car park stays a car park while the shop behind it
burns. Collapse asks it and one more, because a back yard and a town park
both have something to burn and neither has a roof to lose: a region that
was already open to the sky is not a candidate, however well it burns.
That is read once at build time, because gutting sets a region's ceiling
to sky and asking later would mean nothing could ever fall twice.


THE PLAYER IS THE CASHIER
-------------------------

At the user's request, and it turned the front end from eight shapes you
walk past into eight machines you can stand inside.

A TILL USED TO BE A SLAB. One rectangle, 180 by 140, raised to bench
height and wearing one texture called CHECKOUT on all six sides of it. As
shop furniture that is defensible — you cannot walk through it, you can
shoot over it, it reads as a till from the doors — and as a PLACE TO
STAND it is nothing at all, because a slab has no behind.

A belted checkstand is a machine with a direction. You join it at the
back, unload onto a belt, walk forward beside your shopping while the
belt takes it to a scanner, pay at the scanner and collect it bagged at
the front. The cashier is not beside you, they are ACROSS it, standing
in a slot cut into the far side with their back to the next lane. Four
things follow, and they are the whole build:

  IT HAS A LONG AXIS and it is the way the customer walks. Which is why
  the band the tills stand in went from 140 deep to 260 — laid out at
  140 there is room for the scanner and nothing either side of it, and a
  conveyor with the shopping piling up down it has nowhere to happen.
  The eighty units come off the first run of gondola, which is now 600
  deep against 680 for the other two. That is what the front run of a
  supermarket usually is: the one nearest the tills, and the one that
  loses floor to them.

  THE SURFACES ALONG IT ARE DIFFERENT SURFACES. A rubber belt 108 long,
  a scale plate with the scanner glass in it, a stainless bagging deck,
  and a nose across the end. Four regions, two heights, five textures.

  THERE IS A WELL IN THE MIDDLE OF THE FAR SIDE that is shop floor, 60
  wide against a player 32 across, open to the cross-aisle behind so you
  can walk into it and shut at the customer end by the nose. Leave the
  nose off and the well is a way round the tills from the shop floor to
  the mat, which is the one thing a front end exists to prevent.

  AND IT IS TWO OF THEM BACK TO BACK, which is why there is a lane
  either side and one well between: a cashier serves the lane they face,
  and the next cashier along faces the other way. Eight stands, sixteen
  runs of counter, nine lanes.

NOTHING ON ONE IS CLIMBABLE, and that is load-bearing rather than tidy.
Every surface is 26 above the floor against a MAX_STEP of 24, so the
shopping piled on the belts can be free boxes — which do not collide —
instead of two hundred sectors. The first cut had the scale plate
recessed to 34, on the perfectly good reasoning that a scale sits down
in the counter. What that bought was a 22-unit step: you could climb
onto the plate, from there onto the belt, and from there walk through
somebody's groceries. The plate is flush with the belt now, which is
also what it is in a shop — the belt delivers ONTO it — and the recess
is painted into the texture where it belongs.

WHAT IS ON IT. A register on the cashier's side at the bagging end, a
card reader on a post on the customer's side of the same band, a bag
rack over the bagging deck, guards down both sides of the belt and the
plate at the end of it that the shopping runs up against, a magazine
rack on the front panel facing the queue, and a lit OPEN sign hung out
over the lane where you can read it from the back of the shop. About
four hundred free boxes altogether, and every one of them declares
itself INTERIOR — a chimney belongs in a block's shell, a tin of beans
on a conveyor does not.

THE SIZE OF ALL OF IT COMES OFF ONE NUMBER. A counter top is 36 inches
and this one is 28 units above the floor, so a unit is about an inch and
a third: a till is 22 by 16 by 24, a card reader is 12 square, a cereal
box is 15 by 10 by 23. The first cut had the register at 34 by 28 by 38,
which is a filing cabinet with a screen on it, and two of them — one per
run, either side of the well — made the place you spawn a corridor
between two arcade machines.

THE SHOPPING IS A PILE AND NOT A LINE, which took two goes. A belt is 60
wide and a tin is 14, so three of them stand abreast on it; the first
cut put one item per row down the middle, which is a row of parcels on a
conveyor at an airport. It is laid in rows now — three abreast where the
belt has run everything up against the stop, thinning to one at the far
end where the next person is still unloading, with something stacked on
top now and then, which is what stops a pile reading as a row of boxes
on a shelf. Deterministic from the lane's own seed, so two builds put
the same tin in the same place and a screenshot is a screenshot of
something. Your own belt is the busiest in the shop, because it is the
one you are looking down.

AND THE PICTURES ARE SIZED TO THE BOXES, not to a tiling grid, which is
the difference between packaging and wallpaper. The nearest carton to
where you spawn is forty units away and fills a good part of the screen;
a pattern that tiles twice across a cereal box is a cereal box nobody
ever printed. So a carton front is one whole carton front, and the
narrow side of the same box shows the left two thirds of it — which is
the one artefact here, and which reads as printed board rather than as a
mistake.

THE QUEUES WERE WRONG IN THREE WAYS and none of it showed until there
was a player at a till to look at them. They were laid on the AISLE
centres, which are the gaps between the gondola runs and not the gaps
between the checkstands — two grids that do not line up. They began at
the far side of the front cross-aisle, so eight lines of people stood in
the open BEHIND the tills queueing for nothing. And every one of them
was turned to north, which is a queue with its back to the till. They
stand in the lanes now, from the person being served at the scale plate
northward, facing the doors — except the one at the front, who has
turned to face the cashier, which is the whole tell that this is a queue
and not a column of people. Five deep, which is what the lane holds: the
length is worked out from the geometry rather than typed, so asking for
eight does not put three of them in the gondolas.

TWO THINGS IT TURNED UP. A trolley had been standing inside gondola
column four since the runs were laid, which nothing had ever asked about
because nothing walks there. And the check that says a shop burnt end to
end comes down was counting the FURNITURE as the shop: a gondola is a
raised fixture inside the building and has always mostly stood — six of
twenty-three, the day that check was written — because a fixture is
small, holds its own fuel, and the frame over one is cooked mostly by
whatever is alight beside it. That was invisible while the shop was
nearly all floor by count, and stopped being invisible the moment the
front end became eight checkstands instead of eight slabs: forty-eight
new fixture regions, every one behaving exactly as the gondolas already
did, and a ratio that fell under a half without one thing having changed
about the building or the fire. The floor is counted as the shop now and
the fixtures are noted beside it: 52 of 67 of the floor comes down, and
16 of 85 of the furniture.

AND HALF A DOZEN FIXTURES HAD BEEN LIVING OFF THE SPAWN POINT. A jet of
flame needs somewhere to land; a round needs a wall four thousand units
away to put a hole in; a target has to be brought out "in front of the
player" with nothing between the two of them; the responders' six
seconds is measured to wherever you happen to be. None of them said so
— they used the player where it stood, and the player stood in a field.
Moving it into a crowd thirty units from a counter broke all of them at
once, and none of them because anything they are about had changed. The
old spawn is kept on the level as `viewpoint`, which is what it always
was, and those checks ask for it by name.

It costs twenty draw calls, everywhere in the level, which is what
sixteen new textures in the block the supermarket is in costs: 271 to
291 standing in the car park, 600 to 620 on the footway, 195 to 216 in
an aisle.


THE ONE IDEA
------------

The fire is a simulation running under the level, not an effect painted on
top of it. There is a grid of FUEL over the whole map, and every cell takes
its value from the sector it lands in.

  a gondola of stock    300      goes up like a gondola of stock
  the stockroom         340
  a produce bin         150
  the aisle between      55      creeps
  the car park            0      will not burn at all, ever

A FIRE LEFT ALONE GOES OUT. That is the requirement, and it is a
statement about percolation rather than about flammability: a fire
crossing a region carries on only if each burning cell lights, on
average, MORE THAN ONE new one before it burns out.

  expected spreads  =  tics alight  x  chance  x  neighbours

Above one and it runs away and takes everything connected to it, and no
player is needed. Below one it peters out, and no amount of waiting
brings it back, because a burnt cell has no fuel left to relight. There
is no middle setting: it either eventually takes the store on its own or
it never does.

IT USED TO BE ABOVE ONE EVERYWHERE, and the requirement was the exact
opposite of the one above: everything indoors went eventually, from one
match, with nobody helping. Measured with the building empty, one match
dropped in a gondola took 91% of the shop, one in a bare aisle took 86%,
and one in the stockroom took 94%. It did not matter where you put it
and it did not matter what you did afterwards.

Asked for the other way round — much slower, self-extinguishing, and the
player having to WORK to burn the place down — every number went under
the line. What that buys:

  A MATCH IS A PATCH        One ignition in the richest stock in the
                            building takes twenty-odd cells, about five
                            metres across, over a couple of minutes, and
                            then it is out. Two tenths of one per cent
                            of the store.
  A WALKWAY IS A WALL       Bare floor is sixty times less willing to
                            pass fire on than a gondola, which puts it so
                            far under the line that fire does not cross
                            an aisle at all. The cross-aisles are real
                            firebreaks now rather than slow ones.
  THE SHELVES ARE THE FUSE  Dense stock is still the most willing thing
                            in the building, so pouring along a run takes
                            the run. It will not jump to the next one.

So you point the gun at the shelving and the shelving you pointed at is
what burns. A full sweep of the shop still reaches a hundred per cent,
everything charred and everything gutted — that is measured rather than
hoped — but it takes walking every aisle of it, which is the point. The
flamethrower stopped being the fast way to do what waiting would do
anyway and became the only way it happens at all.

AND IT ALL HAPPENS MUCH MORE SLOWLY, which is the other half of the same
request and a SEPARATE number. A fire front creeps about one cell every
twelve seconds through dense stock where it used to manage six cells a
second. What moved for that is the CLOCK — one constant saying how many
game tics a fire tic is worth, which has been 2, 6, 18, 3 and is now 10,
each time because somebody watched it and said faster or slower.

THE TWO ARE SEPARABLE AND THAT IS WHY THERE ARE TWO OF THEM. The
expected-spreads figure is counted in FIRE tics, so it is identical at
any interval: the clock decides HOW FAST and the spread chance decides
HOW FAR. Turn the wrong one and you get a fire that is sluggish and
still unstoppable, or brisk and already over.

THE TWO TERMS TRADE EXACTLY, which is the thing to know before touching
either — tics alight and chance multiply, so halving one is the same as
halving the other. Thin fuel is still deliberately long-lived: a cell of
bare lino smoulders for the better part of three minutes and gets
nowhere, which is exactly the picture wanted — a fire lying on the floor,
visibly alight, visibly not going anywhere, until it gives up. It is also
why the fuel grid is floats: as integers the smallest burn rate
expressible was one unit a tic, and for bare lino that floor WAS the burn
rate.

AND NOTHING ELSE LIGHTS ANYTHING EITHER. A person going off used to
throw thirteen burning pieces seventy units in every direction, each of
which lit the floor where it landed — so one shopper exploding in a crowd
seeded a ring of new fires across the aisle they had been running down,
and that was the single largest reason the shop burnt itself down without
help. The pieces still come off alight, because a body going up is a body
going up. They simply do not hand it on. What a burning person still does
is drag a line of fire along behind them while they RUN, which is a
trail you can see and follow and which now goes out behind them.

AND THEY RUN, AND NOW THEY HAVE SOMEWHERE TO RUN TO. A shopper on
eight-tic watch samples the fire grid at nine points around itself —
where it is standing and eight at its scare range — which is what tells
it both THAT there is a fire and WHICH WAY, and the second is the part
one sample cannot give you.

THEN IT HEADS FOR A DOOR, which is the change that made the crowd behave
like a crowd. Running AWAY from a fire in a supermarket takes you to the
back of the shop and then into a corner, because that is what "away"
means inside a rectangle with one door in it: the crowd used to pile into
the frozen aisle and cook. So the map publishes every way out of the
building as a point on the OUTSIDE of it — six fire exits down the flanks
and the two front sliders — and a frightened shopper picks one and scores
its eight compass directions on how much CLOSER to it they get, minus how
hot it is where it would land, looking two steps ahead so it does not
stop one step short of noticing a wall of fire.

Nearest is not enough, and the case that proves it happens most: a fire
at the west end of the mid cross-aisle is nearest to the west mid exit
for everybody in it, including the people the fire is between. So an exit
is charged for being close to the thing being run from, heavily enough to
lose a thousand units of walking — a longer way out you can use beats a
shorter one you cannot. And the choice is re-made about once a second
rather than every step, because a shopper who re-decides every step in
the region where two exits score the same walks on the spot between them.

GREEDY, AND IT WORKS HERE FOR A REASON WORTH WRITING DOWN. Hill climbing
toward a point gets stuck in dead ends and a supermarket is nothing but
dead ends — except that every aisle in this one runs north-south and
opens onto a cross-aisle at BOTH ends, and every exit sits on a
cross-aisle. So from anywhere in an aisle the door is never at your own
y: moving toward the nearer cross-aisle always gets you closer to it, and
the aisle you are in is a corridor to somewhere rather than a pocket. No
graph, no nodes, and seven hundred of them cost eight distance calls
each.

PANIC IS CONTAGIOUS, because nobody in a supermarket finds out about a
fire by seeing flames — they find out because the aisle in front of them
is suddenly full of people going the other way. Without that, a shop this
size behaves as hundreds of independent people who each notice at 320
units, and with a fire six times faster than it used to be most of them
never started moving until it was on them: the front end stood at the
tills while the back of the store burned. So a fright spreads to anybody
within 190 units, and it carries the point being run FROM with it, so a
stampede goes one way rather than each new person choosing afresh.

AND IT HAS TO RUN DOWN, which took two goes. A fright handed on at full
strength is a loop, and it ran for the whole level: six hundred people in
the woods behind the store, none of them able to see a fire, each one
renewing the neighbour who had just renewed them. So what is passed on is
what is LEFT minus a bit — a rumour weakens with every telling — and a
chain of it dies after about a dozen hops unless somebody along it can
actually see the fire and start a fresh one.

Somebody going off frightens a much wider circle than the fire does, so
torching one at the tills empties the front end before the pieces land.

Not Doom's chase with the sign flipped. P_NewChaseDir walks TOWARD a
thing and all its cleverness is about not oscillating in a doorway;
running away is a different problem, because the wrong step is not a
wasted one, it is a step into the fire. And the fallback when the best
direction is blocked is the SECOND best rather than a random one, which
is Doom's answer and is right for a monster that has lost sight of you
and wrong for somebody with a door in mind: the second-best direction at
the end of an aisle is the one that goes round the gondola, and picking
at random instead threw that away half the time.

WHAT IT LOOKS LIKE, MEASURED. One fire in the middle of the shop, no
player, no help, sixty seconds: three hundred of the seven hundred and
thirty-six end up outside the building, scattered across the wood on both
flanks, the bays, the driving lanes, the verge and the road; the fire
takes four fifths of the store in that minute, and nobody alive is still
standing inside at the end of it. The count of people running drops to
nothing after the first wave and climbs back a minute later as the fire
reaches the second run of shelving and finds the people who had gone back
to shopping.

Those numbers used to read six hundred out and fewer than fifty lost,
with a quarter of the store gone, and the difference between then and now
is one change: a person the fire reaches now RUNS.

THE CROWD is the third way fire travels and it is by a long way the
fastest, because the crowd is the only thing in the building that moves.
A shopper the flame touches used to come apart where they stood — twelve
health against eight a tic is a person deleted in the first tenth of a
second — and what the fire got out of it was thirteen pieces thrown a
couple of aisles and a pool of heat where they had been. At the user's
request they now catch, RUN for three and a half to seven seconds
dropping a line of fire behind them, and explode wherever they get to.

That is not a death animation, it is a DELIVERY MECHANISM. Fire spreads
at about a cell a second through bare lino; a burning shopper covers
eight units a tic in a straight line toward a door they are never going
to reach, through the cross-aisles the fire cannot cross by itself, and
then goes off in the middle of whatever is on the other side. Set light
to the queue at the tills and the back of the store is alight in twenty
seconds — not because the fire travelled but because the people did.

AND YOU CAN SEE THEM. Until recently the best thing in this game was
invisible: somebody alight was the ordinary drawing turned fullbright,
and the entire read was carried by the fire they had dropped on the
floor. What you actually saw was a normal shopper standing near some
flames. Three things fix it and it needs all three of them.

  THE FLAME ON THEM   licks of fire thrown off the body every tic,
                      short-lived and rising. They are PARTICLES and the
                      person is moving eight units a tic, so the ones
                      behind ARE the trail — the same pool does the fire
                      and the tail of it, and somebody alight who stops
                      running piles them up on the spot instead, which
                      is correct and costs nothing. Sparks and smoke off
                      them on their own slower clocks, which is the part
                      of the trail that outlasts the flame and goes
                      where the wind does.
  THE SPRITE ITSELF   a fire colour map on the drawing, the same trick
                      as the ice and for the same reason: multiplying a
                      green coat by orange gives a muddy brown coat, and
                      what somebody on fire looks like is their SHAPE in
                      flame. Luminance is kept, everything else thrown
                      away, and that one number picks off the ember ramp
                      — the same eight colours the coals in a burnt
                      aisle use, so a person burning and the aisle they
                      set light to are made of the same paint. Hottest
                      at the feet, because fire climbs: white at the
                      knees, and their face is the last thing left
                      recognisable, which is what keeps them legible as
                      a PERSON rather than a silhouette.
  THE LIGHT THEY GIVE the flame colour is ADDED and not mixed, so a
                      burning shopper is brighter than a lit one — every
                      colour in the ramp is at most white, and a map
                      alone made a person the colour of terracotta
                      standing in a dark aisle. And they pull the store's
                      one fire light toward themselves like everything
                      else that burns, so a torch running down an aisle
                      lights it as it goes.

AND ALL OF IT IS BUDGETED, because a crowd fire is dozens of them at
once and the aisle is already full of the fire's own flames. Nobody more
than fourteen hundred units off throws a single particle — at that range
they are a glow on the shelving, which is the right answer anyway — and
no more than fourteen of them in any one tic. Forty people alight at
arm's length runs a third of the flame pool.

THE TRAIL IS ONE BELOW A THRESHOLD, and that number is the whole of the
tuning. A cell that is ignited starts at 55 heat plus whatever strength
lit it; js/fire.js sets light to anything standing in a cell above 70; so
a trail of 14 starts a FIRE and does not itself set light to the person
it is running past. That cell climbs over the threshold a fire tic or two
later, by which time the runner is fifty units away and whoever catches,
catches off the floor like everybody else. A trail that lights bystanders
directly turns a crowd into a chain reaction with nothing in between, and
the shop dies in ten seconds flat.

It is still a cascade — this whole system sits near its own critical
point, and the survivor count moves by a hundred and fifty on a change of
one in those numbers — which is why the test measures the things that do
not move: the building empties, hundreds leave through doors, and most of
the store goes.

THERE ARE SEVEN HUNDRED AND THIRTY-SIX OF THEM, at the user's request,
up from four hundred and sixty and before that ninety-two. Ninety-two was
a supermarket at two in the morning; this is a different hour of a
different day. The multiplier is one constant in js/maps/sellwrong.js and
every count beside it is the count the old shop had, so putting it back
to 1 puts the old shop back.

MULTIPLYING A CROWD IS NOT THE SAME PROBLEM AS PLACING ONE, and it went
wrong three ways first.

Random placement stops working. Three people dropped into a 560-deep
aisle land apart because there is nowhere else to land; ten do not. So
every run of people is stratified — each one owns a slice of the run and
is dropped inside it — and every placement has to clear 54 units of
everybody already standing, with retries if it does not.

A shopper is a DISC, and every version of the test that treated one as a
point put somebody somewhere they could never leave. The sales floor is a
rectangle, so it cannot tell an aisle from the gondola beside it. The
sector under the middle of somebody is better and still not enough:
eighteen units of shopper flush against the side of a till is a body half
inside the till, and the move check then refuses all eight directions for
the rest of the level. Two more were standing inside a crate of stock,
because the crates go down before the crowd does. So the disc is tested
against three things — the sector it is in, every rectangle that is not
shop floor, and everything solid already placed.

And five times the old shape does not fit. The old shape was almost all
aisle, and an aisle is 160 wide: five times three people in one is a
queue nobody can get out of, and the flee test caught exactly that — a
shopper beside a fire that shuffled twenty-four units in two and a half
seconds because it was walled in by its neighbours. The extra people go
where a busy shop actually puts them: the two cross-aisles in the middle
of the runs, the front cross-aisle, the mat inside the doors and the
lanes at the tills, all of which had nobody on them at all and all of
which are wider than an aisle.

AND EIGHT TIMES DOES NOT FIT EITHER, which is a different failure from
the one above and needed a different answer. Every group is a region and
a count, and the counts were balanced by eye against the region they sit
in; at eight times, eighty people found nowhere to stand in the region
they had been offered and the shop came out at 656 of the 736 asked for.
A shortfall like that is invisible as a number and shows up as the back
of the store being emptier than the front. So there is a last pass that
ignores the regions entirely, offers the whole sales floor a random point
at a time, and stops when the shop holds what it was asked to hold. The
placement predicate does all the work — it will not put anybody on a
gondola, in a till, inside a crate or within 54 of somebody already
standing — so a uniform scatter over a rectangle comes out as people in
the walkable gaps of it.

IT USED NOT TO BE A FREE KNOB AND NOW NEARLY IS. The cost of a crowd is
not the crowd, it is the panicking: an actor deciding where to step asks
every solid actor whether it is in the way, and against a flat list that
is the crowd SQUARED. Measured with no renderer in the way, against a
35 Hz tic, five fires going with a third of the shop running: 0.21 ms at
ninety-two people, 2.0 at four hundred and sixty. Ten times the work for
five times the people, and the reason this section used to end by saying
that another doubling wanted a grid over the actors rather than a scan of
them.

It has one now. ActorGrid in js/actor.js is a hash of cells 128 units
across holding every actor that was ever solid, and the same measurement
is 0.6 ms at four hundred and sixty and 0.8 at seven hundred and
thirty-six — a third of what the scan cost with sixty per cent more
people on the floor, and about three per cent of a tic. The one design
decision in it worth stating: only the POSITION has to be right. Whether
an actor is still solid, still alive and still in the world changes in a
dozen places, and threading grid maintenance through all of them is how
you get a crowd that can walk through a body one time in a thousand. So
a thing that has stopped being solid stays in the grid and the caller
filters it, exactly as it filtered the flat list. The waste is a handful
of entries per cell; the guarantee is that the grid can never disagree
with the world about who is where.

What limits the crowd from here is not the arithmetic any more, it is the
floor: at 54 apart there is only so much shop.

The car park has no fuel at all and never burns, which makes it the safe
room: the one place you can stand and watch what you have done.


SIX FIRE EXITS
--------------

At the user's request, and they are the single biggest change the shop
floor has ever had, because they are the difference between a crowd that
dies where it stands and a crowd that GETS OUT.

WHERE. At the ends of the three cross-aisles, west and east, because that
is where a real supermarket puts them and because it is the only place
they can go: the perimeter of this building is fixtures — produce bins,
the bakery case, the chill wall, the freezers — and a door in the middle
of a run of chillers opens onto the top of a chiller. A cross-aisle is
walkable floor that reaches the outside wall, and there are exactly three
of them.

WHAT IS ON THE OTHER SIDE. The flanks of the parade, which are wood. So a
shopper who makes it out is in the trees at the side of the building, in
the dark, and there are nine thousand units of forest for them to be
somewhere in. That is the hunt, and it is free: no new geometry, and the
wood already burns.

A PAIR APIECE, at the user's request, and the width is what the building
would give. Every cross-aisle in this shop is a hundred and forty deep
and an exit is cut out of the middle of one, so the opening PLUS its
frame has to fit inside that: a hundred and twenty leaves ten units of
aisle either side of the leaves and three either side of the frame. Two
leaves of sixty, which is about what the staff door's are — and a wider
hole in the wall is the one change you can make to a fire exit that is
unambiguously in the crowd's favour, which is the entire reason these
are here.

WHAT MAKES THEM READ AS AN EXIT AND NOT A HOLE: they are LIT. The
cross-aisles are at 0.26 and these are at 0.62, so the end of the aisle
glows and you can see from the middle of the shop where the crowd is
going. That used to be the whole signage budget, on the grounds that a
word in a texture is always the bug — which still holds, and which is
about TEXTURES. A sign is not a texture: it is one repeat on one free box
that will never be tiled, and there is now a lit one over the inside of
every fire door. See THE LAST DOOR THAT WENT UP.

THE LEAF SWINGS, which is the one thing in this engine that has no Doom
precedent at all. Doom had exactly one door and it was a ceiling that
goes up; the front entrance here is already a departure, because a
supermarket slider cannot be faked by a rising portcullis, and it is done
as two quads on a track with the collision lines switched between wall
and hole. A quad on a transform can be MOVED along the wall or TURNED
about one end of it, and the second one is a hinge. So the same class,
the same state machine and the same blocking lines give the entrance,
the six crash-bar doors and the staff door at the back, and the
differences are three lines of spec:

  swing       a leaf on a hinge, turned up to a right angle about the
                (x0,y0) end, instead of a pair that slide along the wall.
                It turns OUTWARD, away from the shop,
                because that is which way a fire door opens and it is not
                a detail: a door that opens inward against a crowd is the
                thing every fire regulation in the world exists to
                prevent. There is no sign to choose in the code — yawing
                by minus ninety takes the leaf's own +X onto the wall's
                outward normal, so an opening declared left-to-right as
                seen from outside swings the right way by construction.
  pair        two of those instead of one, hinged at the two jambs and
                turning the same way — which the fire exits and the staff
                door both are. It is a flag on ONE door and not two doors
                side by side, because two would share the opening's
                blocking lines and overwrite each other's answer about
                whether the door is wall this tic, and because the swing
                direction falls out of the declaration order: two leaves
                hinged at opposite jambs must be declared in opposite
                orders and would therefore always swing APART, like a
                saloon being shoved from inside itself. Turning the far
                leaf through half a circle also pays for itself — its u
                runs the other way in the world, so ONE texture gives a
                mirrored pair with the outer stiles at the jambs and the
                two meeting stiles coming together in the middle.
  panicOnly   the mat under it only trips for somebody who is RUNNING. A
                fire exit is not an automatic door: it is shut all night
                and it opens when a person in a hurry leans on the bar.
                The first cut of these opened for anybody and the shop's
                six fire doors stood open all night with nothing on fire.
                The player counts as such a person at any time, because
                the player is allowed to walk out of a building.

Both faces of the wall are blocked when it is shut, which sounds obvious
and is worth stating: a door that seals the inside face and leaves the
outside one open is a door you can walk round from the car park.

AND THE LEAF IS PAINTED STEEL WITH A CRASH BAR AND A RUNNING MAN, and
neither of those is a word. A supermarket fire door in this country
carries the pictogram and the bar and nothing else, which is lucky,
because the last four textures with lettering on them came down for the
reason further down this file. The bar is the brightest thing on it: it
is the reason the crowd can leave and the player cannot lock them in,
since a fire door has no handle on this side and no keyhole on the other.


AND THEN IT FALLS DOWN
----------------------

FIRST, THOUGH, IT GOES BLACK — which it did not used to, at the user's
request. The store knew three things about the fire: untouched, charred,
gutted. Two stages, both of them a texture swap, and between them
nothing. An aisle could lose half its stock without a pixel of it
changing and then change all at once, so the whole first half of every
region's life was invisible and the second half was a step.

WHAT WAS MISSING WAS NOT ART, IT WAS A WIRE. The simulation has always
known exactly how far through burning every region is — js/fire.js keeps
burnt and total fuel per sector — and there was no way from that number
to the fragment shader. It cannot be a per-vertex attribute: the level's
geometry is batched by TEXTURE, so a region's vertices are scattered
across every batch it touches and updating one region would mean walking
the whole store. So it is a DATA TEXTURE, one texel per sector, updated
once a tic, and every wall carries its own region index as an attribute.
The whole store is a few hundred bytes; the shader reads it with one
fetch. A byte is enough resolution: a 256th of a region's fuel is a tenth
of a second of it burning.

SOOT ARRIVES BEFORE THE FIRE DOES, and it arrives in PATCHES. Where it
lands first is a world-space field, so the soot has a SHAPE of its own
rather than a level of its own, and it spreads across a wall as the
region's number climbs: the lowest-numbered cells first, joining up,
until the wall is black. Nothing about it is per-region except the
number, so two aisles burning at once are never in step, because they
are not in the same place.

A PATCH IS NOT A CUBE, which took a second pass to fix. Every scatter in
here is a hash over floor(wpos * k), and an axis-aligned cell on a floor
or a ceiling is a SQUARE — two scales of them read as a chequerboard of
soot with dead-straight edges, in step with the chequerboard on the
ceiling above. The fix is not a finer lattice, which only makes smaller
squares: it is to MOVE THE POINT before looking it up. A coarse vector
field offsets wpos by most of a cell before the floor(), so a patch comes
out with a ragged outline at the warp's scale rather than a straight one
at its own — and then three scales of scatter over that warped lattice
give it structure at a bay, at a shelf and at a hand. The same warp is
used by the ash and by the coals, for the same reason.

AND THE EDGE CRAWLS, on the same clock the coals run on, which is what
makes a wall halfway through catching still be doing something while you
look at it. The advancing edge is also the only part of it that is HOT: a
scorch mark is orange at its rim and dead black behind it, and that is
one line of arithmetic — the product of the amount and its complement,
which peaks exactly where the boundary is. It is the difference between
soot spreading and a texture fading.

HOW DARK IS NOT A MATTER OF TASTE. It has to match what it hands over to.
The soot rises over a region's first two fifths, holds, and fades out
again across the halfway mark as the charred textures arrive and take the
job over — both driven by the same number, so the hand-off cannot drift.
The first cut of it took the albedo to a fifth, which the room light then
took to nothing, and a 40%-burnt aisle was a black void with shoppers
floating in it. It keeps about half now, patchily, and gets its own pale
ash for exactly the reason charVariant has some: a burnt store dark
enough to be accurate is a store you cannot walk back out of.

The coals arrive on the region's number too, rather than on its stage, so
the first few show up in the recesses while there is still stock on the
shelves and they thicken from there. It all costs nothing where nothing
has burnt, which is most of the game and all of it until you do
something.

CHARRED IS A SURFACE. GUTTED IS A STRUCTURE. They are two stages and the
second one is the end the whole fire is for.

A region that has lost half its fuel is CHARRED: the same room with
everything in it blackened, which is `_B` twins of the forty textures
that can burn. A region that has lost nearly all of it is GUTTED, and
that is not a darker room, it is a room that is no longer there:

  the walls    THE FRAME SURVIVES AND THE SKIN DOES NOT. Studs standing
                 the full height with a noggin across, and the board gone
                 between them from the top down — because fire climbs,
                 and because the bottom of a wall is the last place the
                 heat reaches. A hole with nothing behind it is a hole in
                 the world; a hole with framing behind it is a building
  the floor    slab, ash, and the bits of the ceiling that came down,
                 with the fire visible in the cracks — which is where
                 the light in a gutted aisle comes from
  the shelves  bare uprights, leaning where the heat was worst, with
                 whatever shelf did not fall
  the roof     THREE STAGES, and the last of them is a STEEL FRAME
                 against the sky rather than a hole in the world — see
                 below, because it is the part of a burnt building people
                 actually picture

THE ROOF DOES NOT ALL GO, and getting that wrong made the first cut of
this look like a demolition rather than a fire. Every gutted region
opening straight to the sky left a burnt-out store with no ceiling
anywhere, which is neither what a burnt building looks like nor what
holds one up. A region needs two things to lose its deck: a span long
enough to fall — how many cells of the fuel grid it covers — and the luck
of the draw. Corridors, doorways and small rooms keep theirs.

AND IT GOES IN THREE STAGES, at the user's request, because two was one
too few. What a region used to do was keep a charred deck or become SKY,
and "become sky" draws NOTHING — a sky ceiling is a hole the engine does
not build a surface for — so half a burnt store was a clean rectangular
absence with a hard edge where the next aisle's ceiling was still up.
That is a hole in the world, not a roof that has gone. Now:

  the deck holds    RUINDECK: the charred underside of a roof that is
                      still a roof. Short spans, and the long ones that
                      got lucky
  the deck is holed RUINHOLE, which is MASKED — the burnt-through parts
                      are not drawn at all, so you see the framing under
                      it and the night past that, and the deck is still
                      overhead between the holes. Every torn edge glows,
                      because every hole is somewhere the fire came
                      through. This is the stage that was missing and it
                      is the one that does most of the work: it is what a
                      roof looks like WHILE it is failing rather than
                      after
  the deck is gone  sky, as before — and the STEEL the deck was sitting
                      on, built as real geometry by js/ruin.js

THE STEEL IS THE POINT. A shed this size is a frame with a deck on it;
the deck burns and the frame is what is standing in the photograph the
next morning. So a region whose deck has failed gets joists across the
span at a pitch of ninety-six, beams under them on a column grid of three
hundred and eighty-four, about a third of the joists sagging between
supports, one in six simply gone, and the odd panel of deck still lying
across a bay. Thirteen members over a gutted aisle, twelve triangles
each, in the same batch as every other piece of steel in the building —
the whole ruined roof of a fully burnt store is about seven thousand
triangles and one draw call.

THE ROOF IS ONE ROOF, which is the thing that file exists to get right.
The fire guts REGIONS, an aisle at a time, so the obvious way to build
this is per region and the obvious way is wrong: two aisles either side
of a gutted gondola would each get their own joists, at their own
offsets, meeting the shelf between them at nothing in particular. What is
drawn instead is one LATTICE over the whole world, and a region draws the
piece of it that falls inside its own outline. Which joists sag, which
are missing, how far one has drooped at a given x — all of it is a hash
or a curve over the WORLD coordinate, never a number drawn at build time,
so the steel over one region lines up with the steel over the next and a
rebuild puts the same frame back in the same place. There are twenty
rebuilds in a level.

AND IT IS NOT BLACK, which is a decision and not an error. Charred steel
really is nearly black, and nearly black at this game's brightness —
everything is written to the framebuffer in linear, so a surface at a
tenth of the grey ramp lands at about two of 255 — is nothing at all. The
frame is the only thing in a gutted region with the sky behind it and it
has to read as a shape, so it sits a third of the way up the ramp with
rust in its seams and coals down its web. A coal is bright at any
exposure, and a joist with a line of them along it is legible across a
dark shop in a way a grey bar is not.

FOUR TEXTURES DO ALL OF IT, chosen by which SLOT a surface fills rather
than by what it used to be, because past a certain point a partition, a
chiller surround and a shopfront are the same rubble and forty more
textures would all have had to converge on the same look anyway. THREE OF
EACH, though, because a ruin is not a material, it is an accident: two
aisles that burned do not char identically, and one texture repeated over
a whole gutted store reads as a pattern, which is the one thing a ruin
must not read as. A region picks its own by a hash of its index — stable
across a reload, different from its neighbour's.

IT HAPPENS REGION BY REGION, which is the part worth watching. The roof
goes in patches, so there is a long stretch where half the shop is still
a shop, some of it is a deck with holes burnt through it, and the rest is
open steel with fire in the floor under it — and the join between them, a
hard edge of ceiling against a frame against stars, is the best thing in
the game.

AND ALL OF IT IS STILL ALIGHT. The burning trees have always run an
eight-colour ember ramp against a clock in their shader; a charred wall
was a PICTURE of embers, baked in and dead, at the exact moment the game
most wants to look alive. Now the world material runs the same ramp on
the same clock, so a charred aisle and a charred fir are one fire going
out rather than two effects that happen to be orange. The ramp moved to
js/palette.js so there is one of it.

WHERE THE COALS SIT, with no second texture to say so: a scatter of
world-space cells about fourteen units across, kept only where the
surface is ALREADY DARK — coals live in the recesses of a burnt thing,
and a burnt texture's own dark places are exactly those recesses, so the
texture picks the spots and the shader lights them. Two sines beaten
against each other keep neighbours out of step, the palette index is
quantised to whole steps so it flips between real colours instead of
sliding through the gaps, and it costs nothing at all where nothing has
burnt. The first cut used cells five units across and lit a quarter of
them, which at a grazing angle put more coals on a ceiling than there
were pixels to draw them in and read as television static.

THEY ARE BRIGHTER NOW, at the user's request, and turning them up was
three changes rather than one, because the first attempt at it made them
WORSE. Multiplying the output by two thirds again gave a burnt aisle
covered in pale cream confetti: heat lands near 1 on anything fully
charred, so the palette index clamped at the top of the ramp, and the top
of the ember ramp is #f8d0a0 — correct for the white-hot heart of a fire
and nothing like the colour of a coal. So the index is biased two thirds
of the way down, into #985800 and #c07820, which is what a coal actually
is, and the wave still takes the odd one to the top and back. Turned up
from there they read as fire rather than as litter.

AND A COAL IS A BLOB IN ITS CELL, NOT THE CELL. Lighting the whole cell
makes every coal the same axis-aligned rectangle and every one of them
the same size; falling off from the middle gives it a round edge, a dark
gap between it and its neighbour, and — because the radius comes from the
cell's own hash — a SIZE, which is the detail that makes a scatter of
them read as coals of different ages. There is a second scatter at a
third the size for the SPARKS in among them, much rarer and cut off by a
thousand units rather than two, because a one-pixel bright thing at range
is aliasing and not a spark.

AND THE CREEPING EDGE IS A LINE RATHER THAN A WASH. The rim of a
spreading soot patch is the product of the amount and its complement,
which peaks exactly at the boundary; SQUARED, it peaks in a band a third
as wide, and a band a third as wide can be several times brighter without
washing anything out. It carries two colours now, because a burning edge
is not one temperature: a broad orange shoulder, and a pale core that
only the very boundary reaches.

The light fittings are taken away rather than switched off when the roof
over them goes, because there is no wiring left in a roof that is not
there. That used to be about the picture as well — a row of dead fitting
sprites hanging in the open air over a roofless shop was the one thing in
the shot that said this is a computer program — and now that a light
draws nothing it is only about the light.


WHAT IS LEFT AFTERWARDS
-----------------------

A store that burns down and looks identical afterwards is an animation,
not a simulation. Two things stop that.

EMBERS. A cell whose fuel is spent drops to a low glow and sits there for
most of a minute before going cold, rather than fading out in a second.
Ground you have already taken stays visibly taken, and an aisle you gutted
five minutes ago is still ticking over in the dark behind you.

CHARRING. Every surface that can burn has a charred twin, generated from
the original rather than drawn separately — so a shelf that goes up turns
into a burnt version of ITSELF and stays in register. Three things happen
to it, and all three are needed or it just looks dim: it goes dark but
unevenly, with soot in the recesses so the relief is still legible; it
goes pale and patchy where the ash settles, which is what stops it reading
as "the lights went out"; and a few embers survive in the cracks as the
only saturated colour left.

When a region is half gone its surfaces are swapped, all at once, and the
level geometry is rebuilt. That costs about ten milliseconds and happens
perhaps twenty times in a level, debounced so that six gondolas passing
the line in the same second produce one rebuild rather than six.

The ambient light also lifts as the store goes — partly embers, partly the
roof no longer being entirely there. A gutted store lit only by embers is
accurately almost pitch black, and you still have to find the way out of
it, so accuracy loses that one on purpose.


THE YARD OUT THE BACK
---------------------

Behind the anchor there is a service yard: a strip of hardstanding as
wide as the store and about four hundred and eighty deep, with chain link
along its three open sides and ONE way in and out of it. The gate lines
up with the roller shutter the night crew left open, so the gate, the
dock and the shutter are one straight line through the back of the
building — which is where the lorries would go, and is also the only way
into the yard that is not a walk around the whole store.

A FENCE IS NOT A WALL, and in this engine that is a statement about
geometry rather than a figure of speech. A wall here is the ABSENCE of a
sector: leave sixteen units between two rectangles and the void between
them is the wall. A wall you cannot see through would make the yard a
corridor with no relationship to the wood on the other side of it, and
what is wanted is the opposite — something you see the trees through and
still cannot walk through. So the yard and the wood TOUCH, every edge
between them is an opening, and the chain link hangs IN those openings as
a MIDDLE TEXTURE on a two-sided line: masked, drawn from both sides,
blocking.

WHICH MAKES THE GAP FREE. A fence is a property of LINES, so the opening
is not a hole cut in anything — it is the one line along the back that
was never given any wire. The rectangle mapper splits a shared edge at
the corners of whatever abuts it, so the wood behind the yard is three
rectangles instead of one and the middle one's edge is the gate. Nothing
else in the map has to know, and the map itself throws if that line ever
comes back fenced or if a fifth one ever comes back bare.

AND IT STOPS AT THE TOP RAIL. That needed a new idea in the geometry
builder, because a middle texture had always spanned the whole opening —
which is right for a grating and right for a shop window, both of which
FILL the hole they are in. A fence does not: it is eight feet of wire
standing on a line between two patches of ground that are open to the
sky, so spanning the gap meant stretching the mesh from the tarmac to the
cloud base and tiling it five times on the way up. A line may now say how
tall the thing standing in it is, and the opening is the LIMIT rather
than the answer.

The mesh is two families of forty-five-degree diagonals eight texels
apart, over sixty-four by forty-eight, spanning a hundred and twenty-eight
by ninety-six world units. Eight divides both, so the diamonds run on
across a repeat in either direction with no seam and no half-diamond at
the joint, and one post per repeat puts an upright every hundred and
twenty-eight units, which is about where a real one goes.

NOTHING GROWS IN THE GATEWAY, and that is not luck either. The forest
keeps a margin outside `clearing`, which is the store's own fuel-grid
rectangle — and the yard, being tarmac rather than wood, is inside that
grid for the same reason the car park is. Extending the grid past the
fence is what holds the gate open.

AND THERE IS SOMETHING IN IT NOW. The back of a supermarket is the honest
end of it and this one was four hundred and eighty feet of blank render
with a shutter in the middle. Everything a shed like this actually
carries lives round the back, because none of it is allowed round the
front: eight condensing sets in two banks — the chill wall down the east
side and the freezers behind the butchery both come out here — three
intake cabinets on the wall where the meter reader can get at them, two
skips out where a lorry can get a chain on them, and the caged ladder up
to the roof.

The skips and the condensers are REGIONS, not free boxes, and the yard is
laid as five horizontal BANDS with each of them cut out of whichever band
it stands in. RectMap forbids overlap, so leaving the hole while the yard
is being laid is cheaper than carving it afterwards — the same trick the
trolley bays use, and the opposite of what the town's hedges had to do,
because a hedge crosses lawns that are already down.

Which means the yard is fifteen rectangles now rather than one, and the
chain link had to learn that: the wire goes between every PIECE of yard
and each of its four neighbours, and a piece that does not reach a given
neighbour simply has no line between them. The smoke test learned it the
same way — a check that asked `l.front === yard.index` found two lines of
the eight and failed a claim about fence height with a fact about
bookkeeping, which is the identical fault the cemetery railing check had
when the hedges split the lawns under it.


THE WOOD
--------

Everything past the kerb of the car park is forest: a flat plain of firs,
bushes, ferns and grass, a hundred and seventy thousand plants, nine
thousand units deep on every side. It is eight big outdoor rectangles in
the map, so you walk out of the car park and keep walking, and it is one
module, js/forest.js, that keeps two things deliberately apart.

IT IS PLANTED THE WAY THE GOLF PROJECT PLANTS ITS OWN, which is one cell
of ground deciding what — if anything — grows in it, with the three
classes as a PRIORITY rather than three independent probabilities. Firs
take their share first and are never squeezed, because the canopy is the
forest and thickening the undergrowth must not thin it. Bushes take
theirs out of what the trunks left, through a THRESHOLDED clump noise, so
scrub arrives in thickets rather than as an even speckle. Ground cover
fills whatever is still empty, which is not a demotion: it is the
definition of a ground layer, and it thins out on its own exactly where
the trunks and the thickets are dense. The understory is several plants
per accepted cell, which is the density dial that is nearly free.

AND BUSHES MOVED OUT OF THE CANOPY. They used to be one per cell and they
BLOCKED, so the only way to thicken the undergrowth was to fill the wood
with obstacles. As understory they are several per cell and you walk
through them — the wood reads dense at eye level and is still something
you can run through with a fire behind you. Only trunks stop you, which
is the rule the collision code already had.

WHAT PAYS FOR ALL OF IT is that the plants are cut into square chunks of
ground, one draw per kind per chunk. This forest costs LINEARLY IN
INSTANCES SUBMITTED and not at all in how much of the screen they cover:
measured in a software rasteriser, a hundred thousand plants cost a
second a frame whether they were a wall of green or collapsed to nothing
by a fade in the vertex shader. Collapsing the quad saves the fill; it
does not save the vertex, and the vertex was the bill. So a chunk gets a
real bounding sphere and three.js frustum-culls the two thirds of the
wood behind you for free, and each class hides the chunks past its own
range — the fern carpet is submitted for the ground you are standing on
and nowhere else. Twice the plants, a third of the frame time.

AND THE CHUNKS HAVE THREE SIZES, WHICH IS THE LOD (at the user's
request). A fir at a distance is the same four vertices as a fir up
close, so there is nothing to make cheaper about the tree; what there
is to make cheaper is the DRAW, and with 2048-unit chunks and the firs
kept to sixteen thousand the wood in front of you was two or three
hundred draws a kind — the thing a phone runs out of first. So the
firs and the bushes are built three times over, into 2048, 4096 and
8192-unit chunks of the SAME plants, and each frame every patch of
ground is drawn from exactly one of the three: fine near the eye,
where frustum culling wants small pieces, coarse at range, where forty
small pieces are one draw. The rule that makes it exact is decided
fine-chunk first (Forest._pickLevels): every 2048 chunk gets a band
off its distance — near, middle, far, as fractions of the kind's
range — and a coarse chunk is drawn only when every fine chunk under
it is in a band far enough for it, a fine chunk only when neither of
its parents is drawn. The smoke test builds the wood headless and
counts: from three places, every tree in range is drawn once and the
draws are well under half what fine chunks alone cost. The understory
stays fine; its range is short enough that it is a handful of chunks
already. The burn is painted into every level, so a fir is as black at
range as it is up close.

THE SIMULATION is a grid of 64-unit cells with a byte of state each —
green, alight, gone — and a list of the ones burning. Every cell is fuel
(the floor is dry litter) and a cell with a tree in it burns longer and
throws fire further; there is a wind from the west and the fire moves
with it three times as readily as against it. It percolates — and that
is a separate dial from how fast. The first tuning had a quarter of the
wood gone in eight minutes; simply lowering the chances put the floor on
the percolation line, where whether a match took depended on which
trees stood nearby. So the chances stay high and the burn is long, with
nothing able to spread until it is a third of the way through: a ground
cell smoulders for ten seconds, a tree for eighteen, and one match, left
alone, has a twentieth of the wood gone in about ten minutes and a
quarter in twenty-three, downwind faster than across. The smoke test
runs that match in Node and holds it to those numbers.

AND IT BURNS DOWN. The first cut's tree ended as a charred silhouette
standing exactly where it had stood, for ever, which a burnt fir does
not: a burnt fir is a stump. From nine tenths of the burn the shader
brings what is left of the tree down from the crown and in from the
sides — discarding texels above a line that falls and outside a width
that narrows — until at the end only the foot of the trunk is standing,
ash grey, and it stays that way because a cell's progress never comes
back down. A bush has no trunk worth the name and goes to nothing; the
ground under both is already black. Nothing in the buffers moves: the
quad, the instance and the cell are exactly as they were, and the stump
is a cut. A burnt-out wood is a field of grey stumps on black ground
with the front still burning at the far side of it, which is a picture
this game did not have.

AND IT HAS FLAMES ON IT. The burn map chars a tree and puts coals on
it; a pool of two hundred instanced flame quads, re-parked every frame
on the hottest burning cells near the eye, puts FIRE on it — carried at
the height the front has climbed to and held to the crown, so a fir is
seen burning from the ground up rather than carrying a lantern over its
own head. The flames come from js/fireart.js, like every other flame in
the game.

EACH ONE IS STEPPED TOWARD THE EYE as it is parked, and shrunk by the
same fraction. A flame on a fir and the fir itself are both quads yawed
to face the camera plane, at the same place: two parallel surfaces at
the same depth, which the depth test cannot separate, so the fire came
out chopped up by needles in a pattern that changed every time the eye
moved. Moving it along the line to the eye and scaling it to match lands
it on exactly the same pixels at exactly the same size — a perspective
projection is a scaling about the eye — and the only thing that changes
is the depth it writes, which is the thing that was wrong.

THE DRAWING is instanced billboards: every plant is one entry in a buffer
and each kind of plant is one draw call, so the whole wood is ten calls
and a ground plane. The plants are the golf project's
(github.com/verdictzero/golf): each sprite comes with a BURN MAP baked
from its own pixels — where the coals sit, how black it ends, WHEN each
texel catches, how leafy it is — and one number per plant swept across
that map takes it from green through scorched, alight and charred with
no second set of art. The shader is that mechanism ported. The ground
under it crossfades forest floor into charred dirt from one texel of
burn per cell, so a burnt patch is black to the ground and stays black.

WHAT COMES OFF IT. Embers and smoke are two pools of a few hundred
instanced quads, in two draw calls, and they spawn from a handful of
burning cells sampled near the player each tic — never from every
burning cell, because with a forest alight that is thousands and a
spark two thousand units off is a pixel. The flame out of the gun is
the same class with the fire's own frames on it.


THE GUN IN YOUR HANDS
---------------------

The flamethrower is a model of Vaportrash's, loaded from assets/models/
by a loader that reads exactly what the exporter wrote and nothing more
(js/glb.js), and drawn in its own little scene in front of the world —
low and hard right, the body off the bottom of the frame, the barrel
coming in across the lower right quarter. It is drawn into the same
low-res buffer as everything else, so the painted diffuse goes chunky
with the walls and the palette eats it with the floor.

IT IS THE SECOND ONE. The first was the user's own, built in Blender
with two marker spheres in it saying where the pilot light burns and
where the flame comes out, which tools/prep-model.mjs lifted out of the
mesh and wrote into the file's own extras. The user replaced it with
this one — a fire extinguisher bottle strapped to a green machine gun,
which is a better joke than anything the game could have modelled — and
it arrives with no markers in it at all. So the two points are numbers
in js/weapon3d.js now, in the model's own units, which is the same
answer the extinguisher and the bore got and the same rule the van set:
somebody else's file is not rewritten on the way in.

AND THE NUMBERS WERE FOUND BY LOOKING. A model with no markers has to
be measured, and the measuring was done with pictures: the gun drawn
flat from its left, from above and straight down the barrel, over a
grid ruled in its own units, with a crosshair on the two candidate
points that was moved until it sat where it belonged. The nozzle is the
middle of the bore inside the C-shaped muzzle bracket; the pilot is the
lip of the little gold igniter pipe that runs under the barrel and
turns up in front of it — below the nozzle and further forward, which
is how the old gun had it too and is what a pilot light is for. Neither
could have been read off a bounding box: the box's centre is inside the
metal and the pipe is a different part from the barrel.

The pilot is a small flame sprite parked on one anchor, the muzzle
flame grows out of the other along the barrel, and the stream that
flies into the world is born at that same nozzle — projected as a ray
out of the gun's scene and back into the world's, so it always leaves
the end of the gun you can see, whatever the two fields of view are.

BOTH STREAM WEAPONS ARE HELD AT ARM'S LENGTH AND THEN SOME, at the
user's request: the flamethrower three times as far from the eye as a
gun used to be, the extinguisher rifle nearly the same. It is one
number each (`out` in the GUNS table, a multiple of how far in front of
the eye the scene parks a gun) and it buys the LENGTH of them. At one,
a quarter of a gun is behind your eye and the rest is too close to
read: what you saw of the flamethrower was a red bottle and a corner of
green. At three the whole weapon is in front of you — muzzle, bottles,
receiver, grip — the bottle is a third of what it was, and the
extinguisher is finally a fire extinguisher with a stock on it rather
than a red cylinder. The cerebral bore keeps its own 1.33, being a
different request: smaller, not longer.

AND THAT IS WHERE THE GUN IS DRAWN, NOT WHERE ITS FIRE STARTS, which
had to be split the moment the guns moved. The world takes the nozzle
as a RAY out of the eye and puts the birth of the stream somewhere
along it; the distance used to be the drawn nozzle's own, forty-two
units, which is a little past arm's reach. Holding the gun three times
further out would have carried that to seventy — the far side of a
shelf you are standing against — so the distance is capped at
NOZZLE_REACH, forty-six, which is what the longest-reaching gun
measured before any of this. The picture moved; the level did not.

WHAT THE PREP TOOL TAKES OFF IT, on the way in, is two thirds of the
file: 6.8 megabytes to 3.3. The maps an unlit renderer cannot use (a
normal map and a metal-rough map, a megabyte and a half between them);
the vertex attributes it cannot bind, which on a Sketchfab export is a
TANGENT for the normal map that has just gone and four sets of UVs for
light maps this game does not have; and then — the part that actually
saves the bytes — a repack that gives every accessor a tight buffer
view of its own. A bufferView is a RANGE, and an exporter is free to
park twenty accessors in one, so deleting the attributes saved nothing
at all until the geometry was copied out element by element at the
source's own stride. Every float accessor that came with a min and a
max is measured again out of the bytes that were written, and a
mismatch throws, because a repack that bends the model quietly is worse
than no repack.


THE ROAD, AND WHO COMES DOWN IT
-------------------------------

IT IS A LOOP, at the user's request. There were two roads and they did
not meet — a frontage lane along the front of the lot that stopped dead
at both ends, and a traversal road across the far end that ran on through
the wood — which is fine until you stand at the west end of the lot and
look at where the tarmac simply stops. Now there is one PERIMETER ROAD
all the way round the car park: four straights, four junctions, and the
public road crossing it at the two bottom corners and carrying on into
the trees in both directions. Which is what a lot this size has — nobody
drives through a strip mall's parking, they drive round the edge of it
and turn in — and it is also the only firebreak in the wood, so the loop
is the shape of the safe ground.

Which order the bands are in is the whole reason the through road is at
the far end. A road, then a car park, then a shop, in that order, is what
arriving at a supermarket looks like; a road against the shopfront with
the car park behind it is not a lot, it is a forecourt. You start on the
verge south of it, so the opening shot is across a road, over a car park,
at a supermarket.

A STRAIGHT IS FIVE STRIPS of sector — an edge line, a lane, the centre
line, a lane, an edge line — because a floor is textured to the world
grid and a 64-unit tile cannot hold one line across a 300-unit road, but
a strip six units wide wearing a tile that is line all the way through
can. That same world-grid mapping is why there are TWO centre-line
textures: a tile whose dash runs along x draws one solid unbroken stripe
down a road that runs along y, which is a different marking meaning a
different thing, so the two legs of the loop wear ROADLINV and the two
straights wear ROADLINE.

AND A JUNCTION IS THE PART EVERYBODY LEAVES OUT. Two things happen at
one and both of them are ABSENCES: there is no centre line through it,
because you do not paint a lane divider across the place two streams of
traffic cross, and the edge lines TURN — they run down whichever sides
are still kerb and stop dead at the sides that are a mouth. A ring road
with its dashes carried straight through its own corners reads as two
roads laid on top of each other. The two bottom corners are T-junctions
rather than bends, so they get the other thing a junction has: a give-way
bar across the mouth of the minor road, which is the marking that says
"this is a junction" before you have looked at anything else.

THE SWAT COME DOWN IT, at the user's request, and they are the first
thing in the game that fights back.

WHAT CALLS THEM IS THE TRIGGER, at the user's request. Not the fire — a
supermarket alight is the fire brigade's business — and no longer the
first body either: ONE SHOT out of any weapon, on the tic you fire it.
SIRENS across the middle of the screen and the first convoy is already on
the road. It used to be the first kill and a sixteen-second wait on top of
it, which together read as the game giving you a head start; there is no
head start now, and the sirens are the answer to the flamethrower rather
than to the body. (A death still calls them, for the night the fire kills
somebody on its own after you have stopped firing — but in practice you
fire first, because firing is how anything in this game begins.)

AND THEY SPEED IN. From the shot to a van standing in front of you is
THREE AND A HALF SECONDS if you are outside, at the user's request, and
this is the third time that number has come down: thirty-five, then
fourteen, now this. Four things make it.

They come in at whichever END OF THE ROAD is the shorter drive to where
they are going — the two are nine thousand units out from the ring on
either side, so guessing wrong was half a minute of tarmac.

The van does THIRTY-SIX units a tic, and it is a top speed now rather
than a constant. Fifteen was twice a running shopper; thirty was a van
with its lights on at two in the morning; sixty was not a van at all, and
the user said so. Thirty-six with a standing start and a braking stop
averages well under itself, which is why the clock kept getting shorter
while the driving got slower.

AND IF THEY ARE COMING FOR YOU THEY DO NOT DRIVE THE ROAD AT ALL. The
map's way in starts where the road leaves the world, and crossing it was
five of those fourteen seconds — five seconds of a van driving down a
road that nobody standing in the car park can see. So the whole way in is
built as it always was and then CUT SHORT from its far end: they come
into being on the road eleven hundred units back from wherever they leave
it, which is about two seconds once the standing start and the braking
are paid for.

AND NEVER SOMEWHERE YOU ARE LOOKING. Eleven hundred units is four van
lengths — near enough to watch one appear, if you happen to be facing
that way. So the spot is walked further back, five hundred at a time, for
as long as it is inside your view: face the road and they come from
further off, face the shop and they are on you in two seconds from behind
your shoulder. It is a view cone and a walk down a polyline, both pinned
on their own in the test, and the invariant the route is held to is the
honest one — the place it comes into being is out of sight, OR the search
spent every try it had. The second half has to be in it, because walking
back along a RING can bring a point round the other side of the lot and
into view again.

THE CUT ONLY EVER TOUCHES THE ROAD. The lead — the last leg, off the
tarmac and in toward you — is appended afterwards and never trimmed, or a
van would come into being in the middle of the car park.

Inside the building nothing changed: you are not watching the road, and a
van that has come the whole length of it is the same van. Both routes are
built the same way and the test holds them against each other: two and a
half thousand units coming for you against eighteen thousand coming for
the doors.

It is the user's police van, an armoured assault truck loaded the same way
the customers' van is (see THE ART) and drawn as its own mesh on its own
sheet, because it can never be in the slab with the others and, unlike
them, it MOVES: in along the through road from whichever end it was sent
to, round the perimeter loop the short way, and off it toward you. The
route is the map's (level.swatRing, level.swatRoutes, level.swatBays; the
lot's own numbers are in scope there and nowhere else), the driving is
SwatVan in js/vehicles.js. It does not stop for anybody: a crowd running
from the fire is a crowd in the road, and a squad van at speed goes
through it; the player is shoved and hurt.

AND IT IS A LITTLE BIT OF A CAR PHYSICS NOW, at the user's request. The
position still rides the polyline exactly — there is no grip, no slip and
no mass — but the SPEED along it is integrated rather than assumed, and
the body is hung off it.

IT BRAKES FOR THE END OF THE ROUTE, not for the next corner, on the
oldest trick in the book: the fastest it is allowed to be going is the
speed from which it could still stop in the distance it has left. So it
comes off the ring already slowing and rolls the last two lengths into
its place, instead of arriving at speed and switching off. It leaves from
a standing start for the same reason. The test records the speed and the
distance remaining on every tic of a real drive and checks that the first
never exceeds what the second allows.

AND THE BODY SHIFTS ITS WEIGHT. Two damped springs, one on the pitch and
one on the roll, driven by what the drive just did to its speed and its
heading. The nose goes DOWN under braking — measured, not asserted: at
two and a half degrees of pitch the nose sits nine units below the tail
in world space — the tail squats under power, and it leans OUT of a bend
the way a real one does, because it is the outside springs that compress.
When it stops it rocks back through level and settles. Five degrees of
dive, four and a half of squat, five of lean, and about a second to stop
moving.

Neither spring is simulated from a suspension: they are the acceleration,
read twice, through something that overshoots. SPRING and DAMP are the
whole of the character — undamped it wobbles for ever, critically damped
it slides into place with nothing to say. It costs four numbers and it is
the difference between a model sliding along a line and a van pulling up.

THREE AT A TIME, at the user's request. Where one van used to be sent,
three are: a convoy, nose to tail from the same end of the road, each
going to its own place. The budget went up by the same factor — six on
the road at once at the start instead of two, twenty-seven at the
ceiling instead of nine — because sending three into a budget of two is
sending two.

AND THEY COME TO WHEREVER YOU ARE, AND THEY NEARLY HIT YOU. Inside the
building they pull up across the fire lane in front of the doors, which
is what the fire lane is for and what the map's bays say. ANYWHERE ELSE
the destination is YOU: a point on the perimeter road, reached by
entering at the junction and walking the ring the short way round, and
then off the road toward you for as far as the tarmac holds — up to
twenty-six hundred units of it, stopping a HUNDRED AND TWENTY short.

Three hundred is to the MIDDLE of a van two hundred and fourteen long, so
its nose ends up about two hundred units off — half a van of daylight.
This is the third number it has been and the user's second thought about
it: two hundred and sixty was called too far away, a hundred and twenty
put the nose thirteen units from your face, and three hundred is near
enough to be in your way and far enough to be a van rather than a wall.
Braking into it rather than stopping dead is the other half of why it
reads differently; see below.

AND IT IS THE BEST POINT ON THE RING, NOT THE NEAREST ONE. Taking the
nearest is right whenever the ground between the road and you is open,
and wrong the moment something is in the way: stand in the trees and the
nearest point has a wood between it and you, so the van gives up at the
kerb — while a point further round, with the tarmac of the lot in front
of it, would have got most of the way. So every free place along the ring
is walked and the one that ENDS nearest you wins, and the search stops
the moment one lands within a step of the stop distance, which out in the
car park is the first one it tries.

Stand in the middle of the lot and a van leaves the road, drives between
the rows and stops with its nose forty units off you and its side door
facing you, three to five seconds after you fired. Stand in the trees and
it stops at the treeline — a van is not going into a pine wood, and the
crew that gets out of it will walk in, because THEY respect the trunks
(see Forest.blocks). Stand behind the building and it gets as far as the
frontage lane and the crew walks the rest: the service yard is drivable
ground with no drivable ground connecting it to the lot, which is a fact
about the map rather than a shortcoming of the driving. The loop is
published by the map as four corners (level.swatRing) and every question
about where a van goes is a distance round it; see js/responders.js,
which is where the ring arithmetic lives.

THEN THE CREW. Parked, it unloads a trooper every second and a half onto
the ground, six of them, out of the side facing YOU — which used to be
the side facing the shop and was the same thing only while every van
stood across the fire lane. When the crew is out it does not stop: it
trickles, one every nine seconds to begin with, for as long as it stands
there — which is for ever, because the van is FIREPROOF (below) and
nothing in the game ends one.

AND IT RAMPS EXPONENTIALLY, at the user's request, and the ramp is one
number: the PRESSURE, 1 at the call and doubling every seventy seconds
from then on, without limit. Everything that says how much police there
is — how many vans may be on the road or standing at once (five, to begin
with), how many troopers may be on their feet across every van (five),
how long between sends (sixty seconds, give or take a fifth), how long
between one trooper and the next out of a standing van (ten) — is that
starting value times the pressure, read off the curve at the moment the
question is asked rather than fixed at the call. So a minute and ten
seconds after the first shot the vans come twice as often and twice as
many are allowed out; two and a half minutes, four times; and the same
minute of the night is the same everywhere, because it is one curve read
four ways. The floors (a send every seven seconds, a trooper every three)
and the ceilings (twenty vans, sixty troopers on their feet) are what the
engine is asked to carry, not the design; the curve reaches all of them
inside five minutes and then holds the lot there. At the doors the map's
nine bays used to be the real limit and are not any more — when they are
full the next one stands along the ring by the doors instead of not
coming. It is js/responders.js, top to bottom, and pressureAfter() is the
curve as a pure function for the test to pin: equal steps in time
multiply by the same amount, which is what exponential means. There is no
goal in this game and this is the nearest thing to an ending it has: the
night gets worse at a rate that does not care how well you are doing.

A SMIDGE LESS OF ALL OF IT, at the user's request, and the second pass
over these numbers. The doubling went from sixty seconds to seventy, the
four starting values each lost one, and the two ceilings came down a
quarter. Nothing about WHEN the first convoy arrives moved — that is the
run-in and the speed above, which the user asked for and which stay — and
neither did the size of a send. Standing still in the middle of the lot
and never firing again, so nobody dies and the count is what the budget
allows rather than what you let live:

              was                 now
  1 min       11 troopers          9
  2 min       23                  16
  3 min       47                  29
  4 min       80, the ceiling     53
  5 min       80 + 15 army        60, the ceiling, + 9
  6 min       80 + 31 army        60 + 17

The army's own numbers are untouched — it is the newest thing here and
there is not much of it — but it starts later anyway, because its trigger
is a PRESSURE on this curve rather than a time, and this curve now takes
three and a half minutes to reach it rather than three. That is the whole
argument for writing a threshold in the units of the thing it is a
threshold on.

A TROOPER IS THE ZOMBIEMAN with the numbers looked at again, and he walks
on the chase this file has described for a year with nobody in it —
A_Look, A_Chase, P_NewChaseDir, untouched. Sixty health, so the stream is
held on one for a moment rather than waved past; a rifle at anything he
can see, face-fire-face on Doom's own ten-eight-eight, three to fifteen
off whatever the shot meets first with the Zombieman's five and a half
degrees of spread either way, which at point blank never misses and across
the car park mostly does; one hit in five makes him flinch. They are a
TEAM, and since the army came the team is everybody who turned up: a
round from one of them does NOTHING to another of them, and neither of
them turns round about it. Doom's infighting is the best thing in Doom
and the wrong thing for a squad, and the damage half of it is worse than
the grudge half once there are two forces on the same ground — a hundred
and forty of soldier that crosses a fire lane with twenty-six troopers
firing down it arrives at twenty, and an army tier that turns up already
shot to pieces by the tier below it is not an escalation. A round is
still STOPPED by whoever it meets, though, so the man in front of you is
still cover and a crowd of them is not a crowd of clear shots; and
anything that is not a round still lands, including their own van running
them down. They come out already after you.

THE TROOPERS ARE FIREPROOF, at the user's request, and it is one flag
(`fireproof` on the actor type in js/states.js) asked in the handful of
places fire arrives: Actor.damage refuses anything flagged `fire`, which
is the stream, the burning floor, a blast and a torch running past;
Actor.ignite refuses to light one because a fireproof thing is not a
flammable thing; and the floor fire does not bother asking. The stream
splashes off the armour and heats the tarmac under it. Nothing eats a
trooper to ash; the two ash states are gone with the flag that reached
them. What still gets through: YOUR bullet, a van (his own, if he is
standing in the lane when the next one comes), and the bore — which is
the answer to them, and is rationed, which is the point. The flamethrower
is not the answer to a man in armour any more than it is to a bullet.

THEIR VEHICLES ARE NOT, ANY MORE. They were — the same flag on the
Vehicle, which for a vehicle means invulnerable, since fire is the only
thing that ends one — and at the user's second request they are ARMOURED
instead: they catch, they char and they go up exactly like the customers'
vans, MUCH more slowly. Which is the better answer, because "you cannot"
and "you can, at a price" are different games and this one was always the
second.

Two numbers, both 1 for a car in the lot: `fireArmour` is what fire's
damage is divided by on the way in, and `charFuse` is what the blackening
is multiplied by once the health has gone. Eight and four for a squad
van, fourteen and six for the APC. Measured in the browser by holding a
fire on one of each:

  a hatchback in the lot        9.7 seconds, flame to wreck
  a squad van                  44.6
  an APC                       about ninety

The armour is only against FIRE. A bullet, a bang and a van are the same
to a squad van as to a hatchback; what it is built to stand in is the
burning. And burning one out of the fire lane gives the bay back, which
never came up while nothing could end one — a wreck that still held its
place would close that bay for the rest of the night.

THE COLD STILL WORKS. A trooper freezes like anybody else, on his own
drawing, and a block of ice with a rifle in it is the best joke the two
weapons together tell. And it is the one place fire does anything to a
trooper: fire on a fireproof block of ice is a THAW, not the execution it
is for a shopper, because nothing inside can be eaten — the old melt rule
from before burn-away, kept for the one kind of person it is right for.
Freeze one and the flamethrower lets him out, running; the bore or a blow
is what finishes him. Fire on the floor under a frozen trooper thaws him
the same way, where it would eat a shopper.

AND YOU CAN BE HURT NOW, THROUGH THREE LAYERS. There was no health on the
screen because nothing could take any off; from the first bullet that
lands there are THREE bars in the corner, at the user's request, and not
before, because a full bar that never moves is the plate of numbers that
corner got rid of.

They are the user's numbers as well as the user's idea: an OUTER PLATE
worth ten of you, an INNER PLATE worth five, and then you — a thousand,
five hundred and a hundred, sixteen hundred in all, against a trooper's
rifle that does three to fifteen a round. They are spent OUTSIDE IN, and
that order is the whole feature: this is not Doom's armour, which takes a
third of every hit for as long as any of it lasts and so drains alongside
your health rather than in front of it. A layer here takes the whole of
every hit until there is none of it left, and only the overflow reaches
the next, so one hit big enough goes through all three in the same call.
That is what makes a stack of three bars worth drawing — the top one is
the only one moving, until it isn't. Blue, then the purple this palette
keeps for bruises, then the old bone-amber-red one that ends the night in
aisle five like the card always said. It is js/player.js: three fields, a
loop over two of them in damage(), and nothing else in the game knows.

AND THEN THE ARMY COMES
-----------------------

At the user's request, and in the order the user set the day the sheet
arrived: the SWAT, then the army, then a super army after them whose
drawings are still to come. The army sat cut and unused in assets/people/
for a while because the piece that was missing was not the soldier, it
was the thing that brings him up the road; the user's HOVER APC is that
piece, and the army was built the day it arrived.

IT IS A SECOND FORCE, NOT A HARDER VAN. That is the whole of the design
in js/responders.js: FORCES is a row per force — which troop gets out,
which model it gets out of, which class drives it, and a block of numbers
— and everything under it takes a force as an argument. Both forces are
on the road at once and neither stops. The super army is a third row
there, a third entry in js/people.js, a third call to troopStates in
js/states.js and a third kit in js/sprites.js. Four tables and a sheet.

THEY ARE CALLED AT A PRESSURE, NOT AT A TIME: when the night is pressing
TWICE what it was at your first shot, which on the police's own doubling
clock is seventy seconds in (it was eight times and three and a half
minutes; the user wanted the army sooner). Writing the threshold in the units of the
escalation rather than in seconds means retuning the doubling moves the
army with it instead of leaving it stranded. From that tic the army has
a curve of its own STARTING AT 1 — so it arrives small underneath a
police force already twofold, and then doubles on the same clock. Both
curves run to the end of the night.

FEWER AND HEAVIER is the difference in every number. Two carriers a send
against three vans; two on the road at the start against six, ten at the
ceiling against twenty-seven; four soldiers on their feet against six,
forty at the ceiling against eighty. But eight in the back of one against
six, a soldier out of the ramp every forty tics against fifty, and a
soldier who is two and a third of a trooper: a hundred and forty health,
one flinch in eight instead of one in five, nineteen hundred of rifle
range instead of fifteen, and a TWO-ROUND BURST off one frame at four to
twenty a round with the scatter halved — two and a half times the damage
out of one squeeze at half the spread, which across a car park is the
difference between being shot at and being hit. The soldiers are
fireproof on the same flag the SWAT wear and they freeze on the same one;
the carrier is not, and is the most fire-resistant thing in the game —
fourteen times the armour of a hatchback and six times as long turning
black. The bore is still the answer to the men and it is still rationed.

AND THE CARRIER HOVERS, which is the first vehicle in this game that does
not touch the road. The model says nothing about it — a GLB has no
opinion — so all of it is in ArmyApc (js/vehicles.js). It rides
thirty-four units off the tarmac and it is never still and never level.

THE BREATH IS TWO SINES, on periods that do not divide into one another:
a four-second one with a ten-second swell under it. One sine on its own
is a metronome and the eye finds it in about three cycles; two is a thing
being held up by something that is not quite managing it. Seven units
either way when it is parked and a little under half that while it is
moving, at the user's request and for a reason — a hovercraft at speed is
held steadier by the ground under it and one standing still wallows, and
the bob you actually watch is the parked one. Measured: twenty-nine to
forty-one units of air standing, thirty-one to thirty-six on the road.

AND TWO MORE SLOW SINES put a degree of pitch and a degree and a half of
roll into it and take them out again. Those are not a movement, they are
what the SPRINGS SETTLE ONTO — `restPitch` and `restRoll`, which is how
the same suspension that serves a van serves this. A parked van's springs
reach zero and are then left alone for the rest of the night; a parked
carrier's are settling onto something that keeps moving, so it never
arrives and is never asleep. Two point two degrees of pitch drift and
three point one of roll, parked, measured over four hundred tics.

AND IT BANKS INTO ITS TURNS AND PITCHES UP TO STOP, which is SwatVan's
two springs with both signs turned over — and turned over for a reason
rather than for the look. A thing on springs leans OUT of a bend, because
the outside springs compress, and dips its nose to brake, because the
weight goes forward. A thing on THRUST has no springs and no weight to
move: to turn it points its lift into the bend, to stop it points its
lift forward. So it banks IN and it pitches nose UP. Given the same
braking left-hander, side by side in the test: the carrier +3.4 degrees
of pitch and -6.3 of roll, the van -2.9 and +2.3. Opposite in both axes,
and the carrier banks nearly three times as hard.

The angles are capped where they are because of the GROUND. At seven
degrees of pitch the nose drops fifteen units and at ten of bank the low
flank drops eleven, against thirty-four of hover with seven of breath in
it. It leans as far as it can without putting a corner through the
tarmac, and the test measures the lowest corner over a whole drive and
holds it against the hover at the bottom of its breath.

It throws GRIT: a puff under the skirts every three tics while it is
moving and every thirteen while it stands, which is what sells the hover
at a distance where seven units of bob is nothing. And you do not get to
walk under it — the three cylinders you cannot walk through stand on the
ground the way every other vehicle's do, and are as tall as the gap plus
the hull. A wreck loses the hover, because nothing that has stopped
working floats.

It is two hundred and sixty units nose to tail against the assault van's
two hundred and forty, and a hundred and thirty-three across against
its ninety-seven: an APC is not a longer van, it is a WIDER one. A hundred
and thirty-three is what fits a fire lane a hundred and sixty deep with
thirteen units of tarmac either side, which is the right amount — it fits,
and it looks like it only just does. It has no siren: two notes still, on
the same clock, but a low sawtooth that rises and falls instead of a
square wave that wails, which is the difference between a thing with an
engine and a thing with a warning.

AND THE FIRE LANE HOLDS NINE, which the curve asks past inside four
minutes. It used to mean the escalation quietly stopped at nine whenever
you were indoors — the one place the design's own "the curve does not
stop" was not true. When every bay is taken the next one now stands along
the perimeter road by the doors instead of not coming, which is the same
answer this file already gave for a player out in the car park. Three
minutes into a night spent inside: twenty-seven vehicles, fifty troopers
on their feet, a hundred and sixteen put on the ground so far.

THE REST OF js/responders.js is still the shape it was: one number, the
ALARM, climbing with how much of the store and the wood has gone and how
long anything has been alight, and six tiers — night manager, security,
the police, the fire brigade, riot police, the helicopter — each with an
alarm they are dispatched at and a delay before they would arrive. That
escalation is written and tested and still records a wave and returns;
the forces have a trigger of their own and do not wait for it.


AND THE AIR SUPPORT THAT COMES WITH THEM
----------------------------------------

At the user's request, and it is the user's model: a VTOL GUNSHIP, close
air support for the army, and the fourth vehicle up the road — the only
one that never touches it. It is js/vtol.js, and it arrived with the
answers drawn into it: two marker spheres named for what they mark, and
the nodes NAMED for what they do (a left-right rotation parent, an
up-down one, a gun to spin). tools/prep-model.mjs reads spheres like
those out of the mesh and into the file's own extras, which it already
did for the flamethrower and the minigun; the new part is that these two
are NESTED, inside the parts they belong to, because where a muzzle is
only means anything relative to the gun that turns. So a marker with a
parent is written down as a point AND a part, and the game hangs the
effect off the node the file names.

IT IS NOT A VEHICLE, though it borrows the vehicles' paint, their pieces
and their arithmetic. A vehicle is one mesh with one transform; this is
a TREE of eight of them — the turret yaws on the fuselage, the gun
pitches in the turret and spins on its own axis, the searchlight pitches
with the gun, the two wing nacelles tilt on the wing and the tail engine
tilts with them — because everything the user asked it to do is a part
moving against another part. Each part is drawn in the vans' own
material, so it is lit, fogged, sooted and charred by the same shader
they are. Eight draw calls and two more for the flares. Four hundred and
twenty units nose to tail against the APC's two hundred and sixty, three
hundred and seventy-three across: an aircraft over a car park of vans.

THE NACELLES VECTOR THE THRUST, which is the request underneath all the
others, and it took two goes. The first one was wrong in three ways at
once, all of which the user saw: the pods were drawn nose-DOWN as it
accelerated and LEVEL in a hover, which is both senses of it inverted,
and they jangled.

LEVEL IS CRUISE ON THIS AIRFRAME. The thing hovers on thrust pointed
DOWN and moves by pointing some of it backward, so the angle each tic is
the angle of the THRUST VECTOR the flight controller has just asked for
— lift under the weight, forward whatever it is accelerating with plus
the drag it is already pushing against — measured UP FROM LEVEL. Holding
station that is a right angle, nozzles straight down. Building speed it
flattens toward the nose. Braking it goes PAST the right angle and
points forward. And DIFFERENTIALLY when it yaws, one pod up and one
down, because that is how a machine with no tail rotor turns. Measured
in the test: holding station the jet is 86 degrees up from level; driven
hard forward it is 37.

WHAT IS DRAWN IS A GEARED SHARE OF THAT, and the reason is the model's
own proportions. Each nacelle is two hundred and eleven units long —
half the whole aircraft — so a pod swung to a true right angle is a
plate the length of the fuselage standing on its edge. Rendered through
the range, it stops reading as an engine somewhere past forty degrees
and starts reading as the thing coming apart. So the pod carries part of
the angle and the nozzle inside it carries the rest, which is a real
arrangement rather than a dodge: a big blended pod with a vectoring
nozzle in it, not a rotating engine. The pods are drawn at 33 degrees
holding station and 3 at speed. The JET is not geared, which is why the
wash lands UNDER it in a hover and streams aft when it is moving.

AND THE PODS ARE A MACHINE, which is where the jangle went. They used to
chase their target through a first-order lag at nearly a fifth a tic,
and the target is read off an ACCELERATION — a controller output, which
saturates against its own cap, comes off the cap the moment the error
shrinks, and steps again at every corner. Every one of those steps went
straight into the drawing. Now the acceleration is low-passed before the
angle is read off it, the yaw rate is low-passed before the differential
is, and the pods themselves are RATE LIMITED: eight tenths of a degree a
tic, which is the pod's whole travel in two and a half seconds. A demand
that jumps cannot make a pod jump. The test throws the demand end to end
every five tics for four hundred tics and holds the pods to their rate.

The tail engine takes most of the pods' angle and LEADS the pitch, doing
what a tail does. The body answers the ACCELERATION rather than the pod
angle — nose down to go, nose up to stop, banked INTO the turn because
it is held up by thrust and not by springs. Hanging it off the pod angle
was the third thing that was wrong: a hovering pod is not at zero, so
the body sat nine degrees nose-down for the whole of a hover.

THE JET WASH is the exhaust arriving, at the user's request. Each
engine's exhaust is a ray from the nacelle down the way its thrust is
not pointing, and where that ray meets something — the tarmac, a wall,
the roof of a van under it — is where the grit is thrown: outward ALONG
whatever it landed on, fast and low and gone inside a second, harder the
nearer the engine. AND IT IS HOT. Anybody standing in a pool of it while
the aircraft is low CATCHES — and it is the PERSON that is lit and never
the floor under them, which is the call that would light a van, because
the user asked for people and not cars. The two wing engines' pools are
a hundred and ninety across and a hundred and sixty either side of the
centreline, so they MEET underneath it: hover over somebody and they are
in one. Cruising at three hundred and thirty up it lights nobody; the
one thing that puts it low enough is coming down over a crowd, which it
goes looking for every eleven seconds and walks across when it finds
one, taking the next the moment the one it is over is alight.

THE SEARCHLIGHT IS A FLARE AND NOTHING ELSE, at the user's request. It
was an actual lit cone for an afternoon — spotPos and its five friends
in js/material.js, added on top of the banded light the way the fire
glow is, on every surface that shades with worldShade, with no shadows —
and it worked: a pale pool about two hundred and forty units across that
you could watch cross the lot. The user has had the beam taken out, and
that is the right call twice over. What it cost while it was there was a
branch and a normalize in every fragment of every wall, floor, car,
tree, sprite and puff in the game; and what it bought was a pool of
light that a beam with no shadow map put through the roof of the shop as
readily as onto the tarmac. One light in that file is the right number,
and it is the fire.

WHAT IS KEPT IS THE LAMP ITSELF, which is what you actually read a
searchlight by at night: A MASSIVE ANAMORPHIC FLARE, at the user's
request. A screen-facing quad whose shader draws a horizontal streak
eight times as wide as it is tall, thin and blue-white, WITH A GRADIENT
SPHERE AT THE CENTRE of it — brightest when the reflector is pointed at
you and falling off as it swings away. The gun has the same thing at a
fifth the size and a warm colour, which is the small flare that stands
in for the muzzle flash.

AND IT IS OCCLUSION AWARE, at the user's request. A flare is drawn over
the top of the frame with the depth test off, so nothing in the renderer
is going to hide it: the three tests are made by hand, every frame, for
each flare, cheapest first.

  BEHIND THE EYE   a flare is sized by its own DISTANCE so that it stays
                   the same size on the screen wherever the lamp is, and
                   a lamp behind your shoulder has a negative one. Left
                   in, the corners project through infinity and what
                   lands on the screen is a white bowtie across the whole
                   frame — which is exactly what the first build did, and
                   the screenshot that found it was blamed on the flare
                   being too big for half an hour before the cause turned
                   out to be the sign of a number.
  ITS OWN HULL     and this is the one that is actually about an
                   aircraft. The lamp hangs under the NOSE, so the
                   fuselage is between you and it from above, from
                   behind and from abeam — most of the sky the thing
                   flies in. The hull is a box in the aircraft's own
                   frame, the EYE is moved into that frame rather than
                   the box out of it (`unturn`, which is js/vehicles.js's
                   `turn` solved for its input, and the test holds the
                   pair against each other), and the sight line is walked
                   against the box. So the flare goes out as it banks
                   over the top of you and comes back as it rolls out.
                   The lamp sits INSIDE that box — four units up off its
                   floor — so every sight line crosses the box just
                   before it arrives, and what separates the hull being
                   in the way from the lamp's own bracket being in the
                   way is how FAR from the lamp the crossing happens.
                   Measured on the model: four to nine units from below,
                   in front or dead ahead; seventy-seven to a hundred and
                   fifty-nine from above, behind or abeam. The clearance
                   is twenty-six, with room on both sides of it.
  THE WORLD        one sight line from the eye to the lamp — the same
                   call a trooper uses to decide whether it can see you —
                   so a wall, a shut door or the shop between you and the
                   aircraft takes the flare away.

None of the three is a hard switch. A flare that pops off at a wall edge
is worse than one that is a few frames late, so what the tests decide is
a TARGET and the flare eases onto it over about a sixth of a second. The
easing is per FRAME rather than per tic, which is allowed here and
nowhere else in this game: nothing downstream of a flare is simulation,
so nothing is made non-deterministic by it.

THE VULCAN is three rounds a tic through the same hitscan the player's
minigun uses, in bursts of about a second with a second between them,
each round its own scatter, each with the minigun's own long tracer
drawn from the muzzle marker to wherever it landed. NO MUZZLE FLASH, the
same answer the user gave for the minigun in their hands, and in its
place the searchlight's flare again at a fifth the size and a warm
colour, flickering at the barrels while they fire. Standing under one in
the open costs about sixty a second, so most of a minute of your health
and armour together.

AND IT CAN BE SHOT DOWN, at the user's request. Three shootable
cylinders ride under it at its altitude — AIRBODY in js/states.js, the
same trick the vans use on the ground — so the minigun's pitched rounds
land on it the way they land on a van: about four hundred and eighty of
them, three and a half seconds of the trigger held on one. Then it GOES
UP. A bang in the air, fourteen fireballs over the airframe, a cloud of
sparks and smoke, the light of it thrown across the whole lot for a
second, ten pieces of its own skin cut out of its own geometry and flung
off it — and then THE TAIL SPIN, which is the part the user asked for by
name. It lurches upward as it is hit, because what is left of the lift
goes into it; then the yaw winds up, the nose goes over thirty degrees
down, the engines are thrown to nothing, and it falls for two seconds
through a turn and a half, trailing fire and smoke and banging every
third of a second. The tarmac is the second bang, and a bigger one: a
blast, eighteen more fireballs, fourteen more pieces, a pool of fire
under it that takes the nearest bay with it, and a wreck that is in the
way, charred on the vans' own two knobs, smouldering for a minute.

WHEN IT COMES: with the army, which is what "accompanies" means here.
Ordered the tic the army is called and overhead eight seconds later —
it comes into being four thousand two hundred units out along the line
to whichever end of the road is nearer, for the same reason the vans do
(see runIn in js/responders.js), rather than at the end of the world,
which was eighteen seconds of empty sky. One of them until the army's
own curve has doubled twice and then two, and one lost is replaced fifty
seconds later. Without the model the army comes alone, which is the same
bargain every other asset in this game makes.


THE SKY AND THE NAME
--------------------

The sky WAS a Polyhaven panorama (moonless_golf, CC0), baked by
tools/bake-sky.mjs to 1024 palette pixels round the horizon, on a sphere
that follows the camera; stars survived the 8:1 downsample because a
block that held a pixel far brighter than its average was pulled toward
that pixel. It is generated now — the same sphere, the same 1024, the
same dither, for whatever hour and weather it is. See THE AIR, THE HOUR
AND THE WEATHER below; the photograph stays in assets/sky, unloaded.

The name is set in Michroma — the open-licensed cousin of the extended
square sans the Flight Simulator wordmark uses, bundled in assets/fonts
so nothing is fetched — as two SVG text lines held to one width by
textLength, MEWD large over DEMO small, the pair skewed
together so they lean as one. The title screen is that and a way in,
over the car park standing still, with the eye wandering very slightly
so the picture breathes. Nothing else on it but the version number,
small and grey in the bottom right corner: one string in js/version.js,
MAJOR.MINOR.PATCH, bumped there and nowhere else, so that a report of
what the game does can say which game.


HOW IT IS BUILT
---------------

It is Doom's architecture, on purpose, because Doom's architecture is right
and because every piece of documentation about how Doom works is written in
its terms.

UNITS ARE DOOM UNITS. The player is 56 tall, 32 across, and steps up
anything 24 or under without noticing. A wall texture is 64 across and 64
up. That last one is the reason for the choice: at 64 units to a 64-pixel
texture the mapping between world and art is one texel to one unit,
everywhere, with no scale factor to carry around.

THE EYE IS AT 49, NOT 41. Doom's is 41 — and Doom drew that on a 4:3
monitor at 320x200, every pixel a fifth taller than it was wide, so the
eye it SHOWED was 41 stretched by 1.2, which is 49. This pipeline
rasterises square pixels — the buffer's height is fixed and its width
follows the window — so 49 here is Doom's eye as Doom showed it.

And it stays 49 with the PIXEL ASPECT set to 5:6, which looks like it
ought to stretch it twice and does not. That setting shapes the GRID the
finished frame is quantised onto, not the frame: the content of a
tall-pixel picture is identical to a square-pixel one, in taller squares.
Doom's 1.2 was a stretch of what it had drawn; this is not one. It was 41 for a long time and nothing
in the store said otherwise, because the store is Doom-sized: a gondola
is taller than you either way. The cars said otherwise. They are drawn at
32 units to the metre, a hatchback's roof is 45 units up, and from 41 the
player looked UP at a hatchback and a van read as a lorry. From 49 a
hatchback is looked down on and a van looked up at, which is what happens
to someone a metre seventy-five tall in a car park.

THE LEVEL IS SECTORS AND LINEDEFS. A sector is a floor height, a ceiling
height, a light level and two flats. A line has a sector on one side or on
both; two sides makes it a hole, with a bit of wall above (the gap between
the ceilings) and a bit of wall below (the gap between the floors). Every
piece of architecture in the store is one of those two pieces:

  a doorway         upper only
  a checkout        lower only, 40 tall, you can see over it
  a gondola         lower only, 80 tall — over your head, so an aisle is
                      a canyon and the next aisle is a different room
  a kerb            lower, 12 tall, walked over without noticing
  a shop fascia     upper, 96 tall, between the canopy soffit and the
                      canopy edge — a band across the front of a building
                      is a ceiling height, because that is the only thing
                      a sector engine has that draws a band
  a parapet         upper, from the canopy edge to the sky
  a produce bin     lower only, 40 tall, wearing crate boards, with the
                      divider between it and the next bin eight higher
  a freestanding    a HOLE: a ring of four thin sectors round a void, so
    object            that all four faces of the void are one-sided walls
                      carrying its picture. An object built out of an
                      absence, which is the only kind a sector engine can
                      make without a new primitive. The pylon sign at the
                      mouth of the car park was one. It has been taken
                      down; the trick has not.
  the back door     a sector whose ceiling is on the floor and rises

WALLS ARE THE GAPS. Two rectangles that touch become an opening between two
rooms — that is what touching means. A wall is drawn by NOT putting a
rectangle there: leave sixteen units between two rooms and the void between
them is the wall. A doorway is a small rectangle bridging that gap, which is
what a doorway is in a real building. js/maps/sellwrong.js reads as a floor
plan because of that one rule.

THE FRONT DOORS ARE THE EXCEPTION. Doom had exactly one door — a ceiling
that goes up — because the renderer could move a sector's height and could
not move anything sideways. Every door in the original game is that, dressed
differently. A supermarket entrance is the one thing that cannot fake:
everybody has walked through ten thousand sliding doors and a rising
portcullis at the front of a SellWrong would be the first thing anyone
noticed. So js/slidedoor.js draws the leaves as two quads on a track,
sitting in the MIDDLE of the sixteen-unit wall void so that opening one
slides it into the thickness of the wall, where there is nothing to draw and
nothing to z-fight with. What they share with a Doom door is the only part
that matters: a shut one sets `blocking` on the lines across the opening and
the collision system treats them as wall. Nothing else in the engine knows
they exist. They open for anybody, not just for you, and once the fire has
been through the entrance they jam part open and stop being a door.

THEY ARE 128 TALL, which is Doom's door height, two and a bit of you, and
the clear opening is 160, so a leaf is 80 wide and stands taller than it
is wide the way a sliding leaf does. They were 210 by 224 — three and
three quarters of you, each leaf wider than it was tall — and read as a
hangar. Above the leaves the entrance sector's ceiling comes down to the
door head, which turns the band between it and the soffit into that
sector's upper texture on both faces of the wall: glazing, a transom,
where there used to be twenty-two units of open air over a 210 door.

THE SIGNS CAME DOWN, at the user's request, and what they had in common is
worth writing down: every one of them was a WORD in a texture that tiles.
The store's fascia is a single 64-wide picture repeating the length of the
anchor, so SELLWRONG SUPERSTORE was written across the front of the
building about sixty times. A vacant shopfront is four tiles across and
four up, so the agent's TO LET board hung on the whitewash twenty-eight
times. The pylon at the mouth of the car park had the opposite problem and
the same cause: it was declared 340 tall on a wall 480 tall, so its board
appeared once where a board goes and then again two thirds of the way down
the post.

A word is a shape the eye locks onto and counts, which is the one thing a
tiling texture must not contain. What tiles honestly is the MATERIAL. So
the fascia keeps its red tray and gets a panel joint at every repeat, which
is a rhythm a fascia really has; the vacant unit's board is a clean
horizontal BAND across a dead tray, which is the only version of "you can
see where the letters were" that tiles — a ghost word would be seven ghost
words; the trolley rail loses its BAY plate and keeps the
bracket it was bolted to; and the pylon is gone along with the eight
rectangles that stood it up. One sign is left on the building and it is the
only one that was never a repeat: the logo over the entrance, which gets
GEOMETRY instead — four tiles hung as a two-by-two, drawn once at its own
size, which is why it was worth the two ceiling steps it costs.

A FIXTURE IS A RAISED FLOOR, AND THE FLOOR IS THE PART YOU LOOK AT. Every
department in the store is a rectangle with its floor lifted to bench or
gondola height and a lower texture round the edge, and every bit of care
here went into the edge, because the edge is what shows in a screenshot
taken from the end of an aisle. The tops were all SHELFBAK — perforated
gondola steel — because a fixture's top had always been gondola steel and
nothing had ever been looked down at.

For a chiller or a shelf run that is right. For fruit and veg it is the
whole department: a supermarket does not SHELVE produce, it BINS it, one
category to an open crate, and the way anybody shops it is by looking down
in. So produce is a run of four bins now — apples, citrus, greens, roots —
with a crate rim between each pair standing eight units proud, which is
enough to throw a shadow line and read as separate boxes from the end of
the aisle and low enough that the run is still one department from the
front of the store. The flowers are three more with pails in them. The
tops are their own pictures at 64 by 64, which is two metres of shop, so a
five-pixel apple is a fifteen-centimetre apple, and each bin is anchored
to its own corner so the packing starts at the crate edge rather than
wherever the world grid falls — the fix the parking bays needed, for the
same reason. Produce is also the brightest thing on that side of the
building, because it is the brightest thing in a real supermarket and for
the same reason: fruit under a dim fitting looks like fruit nobody wants.

THE MAP'S Y IS THE RENDERER'S MINUS Z. A map with x east and y north laid
onto a renderer with x east and z north is LEFT-handed, and everything
still works: movement, collision, the camera, the sprites, all of it
self-consistent, and the picture a mirror image of the floor plan. Nothing
in a supermarket is chiral, so nobody notices — until the day a shopfront
says TO LET and it comes out backwards, and so does the fascia, and so does
the sign at the mouth of the car park. Negating y reverses the screen
winding of every polygon, so every winding in mapgeo.js is written reversed
to match; that is not a style, it is the other half of the sign change.
All three of those signs have since come down. The fix stays, because the
logo over the entrance is still four tiles of artwork and would mirror
just as happily.

LIGHT FROM THE SKY IS NOT LIGHT FROM A FITTING. Doom diminished everything
by distance at one rate, which is right for a corridor and wrong the moment
a level has a car park seven thousand units across: the far end of the
parade came out as a black mass, because the far end of a CORRIDOR should.
So every vertex carries a `sky` term alongside its light — 1 outdoors, 0
indoors, 0.55 under the canopy — and the shader stretches the falloff and
lifts its floor by it. Nothing indoors changed at all.

ACTORS ARE STATE TABLES. Each state says which sprite frame, how many
tics, one function to call, and which state comes next. Read a run of them
out loud and you have the animation:

  RUN: A 4, A 4, B 4, B 4, C 4, C 4, D 4, D 4, and round again

Eight states, four drawings, 32 tics — a bit under a second, which is the
pace of a walk. A_Chase runs on every one of the eight, so the monster gets
eight chances a cycle to notice you have moved.

THE SWAT WALK ON IT. The two staff monsters that used that run of states
are gone, and for a long while the next two paragraphs described a
machine with nobody in it, kept exactly as it was because it was correct
and because getting it correct a second time from the same source would
have taken longer than reading it. Then the squad arrived (see THE ROAD,
AND WHO COMES DOWN IT) and walked on it without a line of it changing,
which is the argument for keeping correct code made in full.

THE CHASE IS P_NewChaseDir. A monster does not path-find. It picks whichever
of eight compass directions points most nearly at you, tries to walk that
way, and if it cannot, works through the others in a randomised order until
something gives. What comes out is a thing that confidently walks into a
shelf, hesitates, slides along it, finds the end and comes round — with no
graph, no nodes, and no map data at all. It refuses to turn round until
there is nothing else left, which is what stops monsters oscillating in a
doorway and is the detail most reimplementations drop.

THE WORLD RUNS AT 35 HZ, always. Every duration in the state tables is in
tics and every movement constant is per tic, so the frame time goes into an
accumulator and the world steps in whole tics. The renderer runs at whatever
rate it likes. Doom's movement numbers are used exactly —

  friction     0.90625 a tic
  walk thrust  0.78125   ->  8.33 u/tic terminal  (292 u/s)
  run thrust   1.5625    -> 16.66 u/tic terminal  (583 u/s)

— because terminal velocity is thrust over one-minus-friction, and those
awkward fractions are 25/32 and 50/32, the numbers in Doom's own table.


HOW IT LOOKS
------------

Everything is drawn into a buffer a few hundred pixels tall, filtered down
onto a grid of chunky pixels, and thrown at the screen with no smoothing.

THOSE ARE TWO SIZES AND THEY USED TO BE ONE. For most of this project's
life there was a single number — the buffer's height — answering two
questions at once: how much detail the world is drawn with, and how big a
pixel is. Which is how it worked in 1993, because the buffer WAS the
screen, and it is a bad control because the two answers pull opposite
ways. Turn it up for a sharper picture and the pixels vanish; turn it down
for the pixels and the far end of the shop turns to mush. There was no
setting at which the store was legible AND the picture was made of visible
squares, which is the look. So there are two now, a tile each on the pause
menu's PICTURE page, each opening a window with a slider that walks the
rungs (see THE PAUSE MENU):

  RENDER    the buffer's height, 120 to 960, on [ and ]. How much the
            world is drawn with, and where the frame rate goes
  PIXELS    the height of the grid it is filtered onto, 120 to 600 or
            OFF, on shift-[ and shift-]. How big a pixel is, and it
            costs almost nothing

IT SHIPS AT 960 AND 320 with 2:3 pixels, at the user's request: the
finest render on the ladder filtered down onto a grid with exactly three
of its rows behind every row you see — 853 by 320 of tall pixels off a
1707 by 960 buffer on a 16:9 window, 640 by 320 off 1280 by 960 on a 4:3
one, and every chunky pixel the average of two columns by three rows,
whole numbers both ways, which is a true box filter and not a set of taps
falling between texels. It shipped at 720 and 240 with 5:6 pixels before
that, at 720 and 200 before that, and at 600 and 300 before any of it:
the render has only ever gone up and the pixels have gone both ways,
because the grid is the LOOK and the buffer is the DETAIL BEHIND IT, and
they are separate dials for exactly that reason. The ceiling on the
buffer's width went from 2048 to 4096 with the move, because a 19.5:9
phone at 960 rows is 2080 across and a 20:9 one 2133, and a clamped
width moves the camera's aspect off the window's — the world drawn a
couple of per cent wider than it is.

The widths follow the window's shape either way, so a wider monitor shows
MORE STORE rather than the same store stretched, and the menu prints both
actual sizes beside their settings, because "400P" says nothing about how
wide it is and the width is where the pixels are.

FILTERED DOWN MEANS AVERAGED, which is the entire reason the two are worth
separating. Point-sampling a 600-row buffer onto a 200-row grid picks one
row in three and throws the rest away — a 200-row picture that cost three
times as much, and two controls that are one control wearing a hat.
Averaging each block spends the extra buffer on the CONTENT of the chunky
pixel instead: an edge falling two thirds of the way across a block comes
out two thirds of the way between the two colours. A 320x200 picture with
every square correct to an eighth of itself is a thing no 1993 machine
could draw, and it is what the setting is for.

AND THE PIXELS NEED NOT BE SQUARE, which is the PIXEL ASPECT ladder beside
them. 320x200 filling a 4:3 monitor is not a square-pixel mode and never
was: each pixel stood five wide to six tall, and every Doom sprite was
drawn by somebody looking at that screen, so a square-pixel 320x200 is a
squashed Doom. The setting is the width of one chunky pixel over its
height — SQUARE, TALL 5:6, TALL 2:3, WIDE 7:6, which is a console's
256x224 on the same screen, or TALL 1:3 — and the grid's width is the
window's shape divided by it. Ask for 5:6 at two hundred rows on a 4:3
window and you get 320x200, which is not a coincidence and is the whole
of the arithmetic.

Nothing about the world moves when that changes. The camera reads the
BUFFER's shape and the buffer's pixels are always square; the grid is a
quantisation laid over a finished frame, and quantising a frame
anisotropically does not stretch what is in it. Two things fall out of
that and are held by the smoke test: OFF means OFF rather than "square",
because with no grid of its own there is nothing for an aspect to be the
aspect of; and when the buffer has not got the columns a shape asks for,
it is the ROW COUNT that gives way and not the shape, because tall pixels
need more columns than square ones and clamping the width would quietly
hand back square pixels and a control that looks broken.

The status bar and the weapon go into the same buffer and through the same
filter, because a crisp overlay on a chunky world reads as a filter applied
to a photograph. The bar is laid out in CHUNKY pixels rather than buffer
ones — its camera is orthographic, so its extents are a unit of measure
rather than a resolution — which is what keeps it the same size on screen
when RENDER moves, and at a whole-number ratio the block average puts each
of its texels back exactly. It is two bars now, and the four numbers and
the notifications that used to be up there are gone at the user's request;
the machinery that posted a message is gone with them rather than left
standing unread.

AND NOTHING IN FRONT OF A WALL IS A WALL, which had been quietly wrong
since the soot went in. Every sprite in the game shares the fragment
shader with the walls, and the block that asks the burn grid "how burnt is
the floor here" is the right question for a surface and the wrong one for
a thing standing on it: shoppers were being given the soot and the live
coals of whatever they stood over, and the smoke — which drifts, and so
sampled a different part of the grid every frame — had the fire's coals
CRAWLING across it. It is a define now, set by the wall material and by
nothing else. Walls, floors, ceilings, the ruined roof steel and the
vehicles are surfaces and burn; sprites are things in front of them.

THE SMOKE ALSO STEPPED. The churn, the sway and the lift all came off the
whole tic count, which advances thirty-five times a second while the
renderer runs at sixty or more, so every drifting puff moved in visible
jerks beside a camera that did not. They read a clock with the fraction
still on it now. The body of smoke over the fire went from eight frames
to sixteen — the loop was always exact, it just was not fine, and a step
every eleven tics of a sprite that size is long enough to watch it hold
still — and each puff KEEPS the cell it is standing over between frames
instead of being re-dealt off a list that re-sorts itself, which is what
had thirty-six of them teleporting. The drifting puffs were four
independent noise fields, so walking them was not a churn but four cuts;
they are eight frames of one field scrolled by an eighth of its height,
which loops.

THREE PASSES, AND IT IS CHEAPER THAN THE TWO IT REPLACED. World into the
buffer; buffer onto the grid, averaged and dithered and snapped; grid onto
the screen, nearest, no arithmetic at all. The palette search used to run
once per SCREEN pixel — two million of them on a 1080p monitor — and now
runs once per chunky pixel, which at 320x200 is sixty-four thousand.

THE FRAME WAS MEASURED, AND THEN CUT
------------------------------------

The town was built, and then the landscaping went in, and then somebody
played it on a phone and got twelve frames a second. So the frame was
taken apart with a profiler in a headless browser — every subsystem
wrapped, timed per frame and per tic, at four places in the map — and
what it found was four things, three of which were nobody's fault and
one of which was a comment that had stopped being true.

Before, and after. A frame's own CPU, and the draw calls the renderer
issued for the world:

                     draw calls        the portal flood      a tic
  a shop aisle     424 ->  197        0.25ms -> 0.12ms
  the car park     974 ->  240        0.52   -> 0.46        3.8ms -> 1.1ms
  a town street    677 ->  548       18.1    -> 0.34        everywhere
  the park         918 ->  798       34.8    -> 1.58

THE COMMENT THAT HAD STOPPED BEING TRUE was over the burn grid. The
shader reads how sooty a surface is out of a picture of the fire's own
cell grid (see THE PICTURE in js/game.js), and the code that filled it
in SCANNED THE WHOLE GRID every tic looking for the cells that had
moved. It was written when the grid was the supermarket — 225 by 207,
forty-six thousand cells — and the sentence over it said so. The town
made it 605 by 810, which is four hundred and ninety thousand cells, and
seventeen million cell reads a second to find the twenty that changed.
It was two thirds of every tic in the game whether or not anything was
alight. The fire keeps a list of what it touched now and the drain walks
that, which is tens of cells; and the picture, which was RGBA in the
power of two over the grid — a megabyte of texels, four megabytes sent
to the GPU on every tic where one cell moved — is one byte a cell at the
grid's own size, and goes up at twelve hertz rather than thirty-five.
Nine times smaller, three times less often, and the scan is gone.

THE PORTAL FLOOD WAS THE BIGGEST ONE. It cost eighteen milliseconds a
frame on a town street and thirty-five in the park — on its own, a
ceiling of twenty-eight frames a second, before anything was drawn. It
was doing exactly what it was written to do; the trouble is that what it
was written for is a SHOP, where it is magnificent (an aisle sees fifty
regions of sixteen thousand and the rest of the crowd is not drawn), and
a town is not a shop. An open street grid hides nothing, so the walk
went through two hundred thousand line crossings to conclude that ten
thousand of the map's sixteen thousand regions were visible, which the
frustum would have said for nothing. Four changes, in the order they
were worth:

  ITS RADIUS. Measured against the radius it is run to, the SHOP
  SATURATES at three thousand units — past that the flood has already
  found everything a wall could hide, and every further unit buys
  nothing and costs the town. It runs to four thousand now (VIS_FAR),
  which fits every indoor space in the game, the fire's sprites and the
  street lamps' flares. Past it isVisible says "visible", because
  nothing out there was walked and an unknown is drawn rather than
  hidden — which is what an engine with no portals at all does.
  Eighteen milliseconds to under half of one.

  THE ANGLES. The walk does exactly one thing with an angle: it clips
  intervals against each other. So it does not need the angle, it needs
  something that SORTS the same way — and that is the diamond angle,
  which walks the unit diamond instead of the unit circle, is monotonic
  in atan2 over the whole turn, comes out already wrapped, and costs a
  divide instead of a transcendental. Four hundred thousand atan2 calls
  a frame, gone. See pseudoAngle in js/util.js.

  THE WORK DONE PER LINE, which was being done per STOREY. The distance
  test and the two angles depend on the line and not on which floor of
  the building is on the far side of it, and they were inside the loop
  over the floors. And the distance test called a helper that RETURNS AN
  ARRAY, two hundred thousand times a frame.

  A BUDGET. Past three thousand regions the walk gives up and says
  everything is visible. It is the honest answer in an open town and it
  bounds the worst case at O(1) instead of O(the town).

  None of it is allowed to hide something you can see, and the test is
  the one that was already there: cast real rays with sightBlocked and
  every region a ray reaches must be in the flood's set. Nine thousand
  ray points at four places, zero misses.

A CROWD IN ONE DRAW CALL PER PICTURE. Every sprite in the game owned a
Mesh and a ShaderMaterial, because the quad is spun and scaled by
uniforms and uniforms belong to a material — so the seven hundred and
seventy-two things you can see across the car park were seven hundred
and seventy-two draw calls, four fifths of the frame's. And they share
TWENTY-EIGHT PICTURES between them, because a shopper is one drawing
that faces every way (js/spriteload.js says so at the top). So they are
twenty-eight draw calls: one InstancedBufferGeometry per texture, with
where each one is, how big, how lit and its four flags in instance
buffers. See js/standees.js.

THE SHADER IS THE SAME SHADER, and that is the part worth copying. The
four values the fragment stage reads per sprite — fullbright, frost,
ash, alight — are declared as VARYINGS under one define, with the names
they already had, so not one line of the body of either stage knows
which way it is being drawn. A crowd drawn in batches cannot look
different from a crowd drawn one at a time, because it is the same code.
The test holds the two materials' shader source against each other and
checks they differ only in a define.

AND THE AIR DECIDES THE DRAW DISTANCE. Every surface is mixed toward a
texel of the sky by its distance, and the mix is nearly complete well
before the air's far limit: at eighty-five per cent of airFar a surface
is ninety-three per cent sky, so what is drawn there is the sky with a
four per cent memory of a roof in it. A block past that is not submitted
at all, and because it is a fraction of the CURRENT air it follows the
weather for free — rain pulls airFar in to five thousand and the town
closes up with it, which is what a town in the rain does.

AND A BATCH TOO SMALL TO SEE IS NOT WORTH A DRAW CALL. Each one knows
how much WORLD it covers (accumulated as it is built, in Batch.tri), so
its share of the screen is that over the square of the distance. Area
and not triangle count, because a road is two triangles and an acre; and
area and not the bounding sphere, because a batch's sphere is its whole
block. The threshold FOLLOWS THE PIXEL DIAL: at 960 rows a pixel is
about 2.3e-6 of a steradian and at 320 it is nine times that, so nine
times as much can go — which is the right way round, because the buffer
that cannot show the detail is on the machine that cannot afford to draw
it. At the default it drops six batches of five hundred and fifty, and
at the coarsest it drops a third of them.

WHAT IS LEFT, HONESTLY. Five hundred draw calls down a town street, and
they are not waste: twenty-seven blocks are visible and each is about
twenty textures, and every one of those batches covers more than four
pixels. Cutting it further means fewer TEXTURES per block, which means
an atlas, which means tiling a sub-rectangle with fract() in the shader
and losing the mip seams — a real project, and not one to start without
first measuring whether draw calls or fill rate is the wall on the
machine that is slow. On the test rig they are: the world pass takes six
milliseconds at 1.5 megapixels and 4.6 at 0.06, so it is the submitting
and not the shading.

AND THE READOUT WAS LYING. The FPS line said "1 draws". renderer.info
resets at every render() call and the pipeline makes four of them — the
world, the overlays, the post pass and the blit — so by the time the
line was written the counter held the blit's own quad. It keeps the
world pass's count now, which is the number the culling exists to move.

WHAT TO SPEND THE FRAME ON. Four settings, and they are in the order of
what they are worth, measured:

  RENDER    the buffer's height, now up to 960. Halving it quarters the pixels, and on
            anything with a weak fill rate that is the whole answer.
            PIXELS is not on this list: it is a look, not a cost, and
            turning it down does not make the world any cheaper to draw
  THE WOOD  how far into the trees the chunks are kept. Twenty-eight
            thousand plants in distance-culled chunks, and pulling the
            range in was worth two to three times the frame rate on its
            own — the single biggest thing in the frame
  CROWD     how many of the standees are drawn. It used to be the third
            most valuable dial on this list because seven hundred
            billboards were seven hundred draw calls; they are
            twenty-eight now, one per picture, and it is worth much less
            than it was — see A CROWD IN ONE DRAW CALL PER PICTURE
  EFFECTS   how much of the fire's sprite pool gets used. The candidates
            are sorted nearest-and-hottest first, so spending less of it
            drops the far, cold end, which is the right end to drop

PALETTE IS ON THAT MENU AND IS NOT ON THAT LIST, because it costs
nothing to draw either way — it is a different game to look at. It is
the box the FINISHED FRAME is dithered down into on its way to the
screen, not the box the art was painted in: RAMPS is the fifteen
material ramps this game was drawn out of, UZEBOX is a real console's
8 x 8 x 4, and the art underneath is the same art either way. See THE
RAMPS ARE THE MATERIALS AND THE PALETTE IS THE BOX OF CRAYONS.

NONE OF THEM TOUCHES THE SIMULATION. The shop is the same shop at every
setting: the same seven hundred and thirty-six people, walking the same
way, running from the same fire and getting out of the same doors. Only
the drawing is cheaper.

TIME AND WEATHER sit under them and are not settings of that kind: the
weather is the night's, remembered, and the time button steps the clock
to the next keyframe for looking at the dawn without waiting for it.
The weather DOES touch the simulation — rain puts fires out and the
wind leans them — which is what it is for. See THE AIR, THE HOUR AND
THE WEATHER. A crowd setting that spawned fewer people would
change who gets out of the building alive, and the smoke test holds that
line — four hundred tics at the lowest setting, and the cast list is
unchanged.

AND THE CROWD CULLS ITSELF. Every standee is its own mesh with its own
material, because the quad is spun and scaled by uniforms, and the meshes
say frustumCulled = false — a quad the shader turns has bounds that are a
lie, so three.js is not allowed to cull any of them. It was therefore
drawing all seven hundred every frame, however far away and whether or
not they were behind you. Actor.render does it instead, with the two
tests that are safe for a billboard: behind the camera PLANE (which every
sprite in the game is turned to, so a thing behind it is edge-on and
invisible by construction) and too far to matter. The cone is generous —
eighty degrees against a field of about forty-eight, because a sprite is
as wide as it is and popping one in at the edge of the screen is worse
than drawing it — and it still takes the shop from about a thousand draw
calls to under eight hundred, and to under five hundred when you turn
round and face a wall.

256 COLOURS. Fourteen ramps, generated, so nothing here is anybody's palette
and there is nothing to attribute. A ramp is a list of stops with the middle
one deliberately off the straight line between the ends, because
interpolating a light brown to black gives a dead grey-brown that no real
material does. Fire gets seven stops and 44 of the 256 entries, because the
store burning down is the only thing anyone is going to look at closely.

Colours are snapped to the palette on the GPU through a 32x32x32 lookup
cube, built at start-up and flattened into a 1024x32 texture. Dither
first, then snap: dithering afterwards would put back colours the palette
does not contain. It is built from the DISPLAY palette — the box the
screen can hold, which is a setting and is not the box the art was
painted in — and it is rewritten in place when that setting changes.

THE DITHER IS ONE STEP OF A 16 BY 16 BY 16 RGB GRID, at the user's
request — it was one step of the cube's own 32 — so the Bayer threshold
can move a chunky pixel a sixteenth of a channel either way before the
snap, and a band the palette would have drawn as two flat colours comes
out as a checker of the two, twice as far apart in colour as before and
visibly so. Three numbers rather than one (a vec3 the shader divides by
per channel), because a channel the eye is worse at could carry a
coarser grain than one it is better at; in the box the game starts in
all three are 16. The sky bake adds the same step off the same GLSL
function, so the sky's grain and the picture's are one grain.

THE GRID IS THE DISPLAY PALETTE'S, not the pipeline's — it lives beside
the colours in DISPLAY_PALETTES, js/palette.js, because how far the
dither must reach is a fact about the box being aimed at. A grid too
fine for a coarse box does not dither it, it puts a seam in the middle
of the band. See AND THE DITHER'S GRID HAD TO GO WITH IT.

THE FIRE IS THE ONE THING DRAWN ADDITIVELY, at the user's request, and it
is the one thing in the game that should be. Doom had exactly one way of
drawing a sprite — a cut-out, every pixel either there or not — and
everything here that is a THING is drawn that way. Fire is not a thing.
Two flames overlapping are brighter than one flame, and it is the adding
that makes a mass of flame read as a source of light rather than as
orange wallpaper. So the flame material adds to the frame buffer and
writes no depth, and the soft edge the flame generator always drew and
the alpha test always threw away is finally being used for something.

A CLUMP, NOT A FLAME. One sprite per fuel cell puts one flame every
thirty-two units on a grid, and a grid was exactly what you saw. Each
cell now gets between one and three, scattered inside it and a little
past it, at offsets HASHED off the cell index and the slot — so the
scatter is random but it is the same random every frame, and the fire
does not boil. Everything that moves in it moves because the flame art is
animating.

BIG IN THE MIDDLE, SMALL AT THE EDGE. `core` is how surrounded by heat a
cell is: the mean of its four neighbours' heat, which is a number the
simulation already has, so it costs four array reads. A cell in the
middle of a burning gondola has hot neighbours in every direction and
gets three big flames; a cell on the advancing front has cold ones and
gets a single small one. That is the shape of a real fire — a bright body
with a ragged fringe. It picks the SET as well as the scale: the outer
members of a clump come off the size below, so a small flame is genuinely
a smaller drawing rather than a big one shrunk.

FEWER, BIGGER, AND AS FAR AS THE AIR. Two things a fire on a town's
scale asked for that a fire in one shop did not. The first is room:
one to three flames on every burning cell was a carpet, and a carpet
is what the pool ran out on halfway down the street. So about half the
cells near you get a flame and a quarter further off, chosen by a hash
off the cell so the choice holds still, and each flame that stays is
drawn bigger than the cell it stands in — a scatter of big fires with
gaps between, which is what a fire looks like, and the same hundred and
ninety-two quads reach three times as far. The second is distance. The
first cut stopped drawing at two thousand units, and a town alight the
next block over was a glow with nothing in it. Past FLAME_MID the
burning cells are gathered into CLUMPS, eight cells on a side, and each
clump is ONE flame at the middle of its fire, sized by how much of it is
alight: a handful of very big fires on the skyline, drawn whatever the
flood says — the flood is flat, and a fire behind a row of houses stands
above their roofs — out to the air's own reach, since the fog has taken
whatever is past that. The wood's flames do the same, from
Forest._placeFlames, so a hillside burning across the valley is a
hillside burning and not a row of dots. The headless check renders one
burning run from three hundred units and from three thousand two
hundred: fewer flames than cells alight the first time, a handful of
huge ones the second, none at all from seven thousand.

AND IT SHRINKS FOR BEING CLOSE, which is the same problem the particle
system solved from the other end. The near cull only refuses a flame
within forty-six units of the eye and it was written when a flame was a
hundred and fifty units tall; a two-hundred-unit blaze on top of the
gondola BESIDE you is a hundred and forty away, passes the cull, and
covers half the screen. Standing in a burning aisle should be alarming
and it should not be opaque. So a flame shrinks with its own distance,
down to two fifths at the near cull. What that costs is a fire that is
not perspective-correct at arm's length, which nobody can see; what it
buys is that you can still find the door.

AND THERE IS SMOKE STANDING ON IT. A fire without smoke is a light.
Everything you would actually notice about a burning supermarket from the
car park is the smoke: it is bigger than the flames by a factor of ten,
it is the thing that gets into the aisle you were about to walk down, and
it is the only part of a fire still there after the fire is out. There
were already drifting puffs — particles, which go where the wind takes
them — and no BODY of it on the fire itself. Now there is: billboards
parked over the cells with the highest core, at a height that rises with
it, alpha-blended and NOT fullbright, so the one fire light in the game
lights them from underneath. Both halves are wanted. A plume that does
not shed is a prop; puffs with nothing under them are litter.

The art churns and loops exactly, by a trick the noise makes free: the
lattice wraps after h rows, so sampling it with a vertical offset of
h/count per frame comes back to itself after count frames. The same field
decides the silhouette AND the shading, so the scroll that stirs the
inside also eats the outline — which is what separates smoke from a grey
ball with a pattern on it. It is the one piece of art here that is not
snapped to the palette: a cut-out edge is what makes a Doom sprite a Doom
sprite and it is exactly wrong for smoke, which has no edge.

LIGHT STEPS, IT DOES NOT FADE. Doom did not multiply a surface by a light
level, it kept 32 pre-darkened copies of the palette and picked one. So
brightness drops a BAND at a time down a dark aisle, and those steps are
half the atmosphere. The material shader quantises light to 32 levels before
it uses it. Doom's fake contrast comes with the same idea: walls running
east-west read a notch brighter and north-south a notch darker, so a corner
is visible in a renderer that does no shading at all.

THE LIGHTS ARE PAINT, NOT OBJECTS. A suspended ceiling is a grid of tiles
with a fluorescent fitting every so often, and "every so often" is the
problem: a 64-pixel texture tiling every 64 units puts a fitting in every
tile. So the ceiling texture is declared as 256 units square — one texture
is a 4x4 block of tiles with a single fitting in it — and the sources land
every 256 units at the same offset. A texel is four units instead of one,
which is nothing on a surface three metres over your head.

There used to be a LAMP SPRITE as well: a suspended troffer hung 34 units
under the ceiling, drawn four ways, with a six-state ring for the
stuttering ones. It is gone at the user's request — the fitting is the
ceiling texture and nothing else. What that costs and what it buys is
below.

THE FITTING IS THE USER'S, from a reference photograph: a four-tube
recessed troffer behind a prismatic diffuser, dark lampholders at both
ends of every tube, a pale works-painted tray with a flange round it.
Thirty-two texels by fourteen is what a 256-unit ceiling texture has to
spend on one, and the ribs are the whole look of a prismatic diffuser
and are two texels wide — one for the facet that faces the light and one
for the one that does not. At one texel they alias into a flat grey the
moment the ceiling is at an angle, which is always, because it is a
ceiling.

THE PLAID IS THE PICTURE, and that is worth saying because it looks like
a mistake. Ribs run across the fitting the short way and four tubes glow
along it the long way, so the face of a fitting is crossed both ways.
The first cut washed the tube rows and the gaps between them by
different amounts and the crossing came out as a chequerboard, which is
what a diffuser does not look like; one alpha the whole height of the
tray fixes it. The bands then have to BEAT the ribs — two bright texels
against one dim one, and the ribs faint enough to be only a shine taken
off — or the fitting reads as a grille, and a grille in a ceiling is not
a light, it is a vent.

AND IT HAD TO BECOME A LIGHT THAT IS ON. The texture was originally drawn
as a fitting that is OFF, on purpose, because the sprite was doing the lit
part: pale ribbed glass at about the brightness of the tiles round it,
neither a hole nor a lamp. With the sprite gone that is a shop full of
switched-off fittings, which looks like a power cut. So the tubes are the
only thing in the game drawn at the very top of a ramp, the tray behind
them is near-white, and the tiles for five texels around the flange are
washed paler — that last part is what actually says the thing is on,
because you can tell from a ceiling alone whether a shop's lights are lit,
and what you are reading is the spill on the tiles. The flange's SHADOW
went with it: a fitting that is lit does not cast one onto the tiles it is
lighting. Measured, in the smoke test, because a flat has no opinion about
whether it is meant to be a light and nothing else in the game would say
so: the fitting is 0.74 against 0.54 of ceiling tile, 0.63 for the tiles
beside it, four bands read as four, and the darkest texel in it is a
lampholder at 0.15. Without the holders a lit troffer at this size is a
white slab, and a white slab in a ceiling is a hole.

A COOL TUBE OVER WARM PAINT. Grey at the top of its ramp is 248,248,252
and bone at the top is 244,238,216 — the same luminance, a different
white — and that split is what makes white read as LIGHT rather than as
more white paint. It is also the entire reason the palette has two
near-whites.

WHAT IT COSTS: every fitting in the shop is now the same fitting, because
a tiling texture cannot be anything else. One in fourteen used to have a
tube gone and one in eleven used to stutter, and both of those were
sprites; the hash that picked them is gone too, because a dim patch under
a fitting that still looks perfect reads as a bug rather than as a
knackered shop.

WHAT IT BUYS, and this was the old objection to painting a light into a
ceiling — that it stays lit after you have broken it — is answered by the
renderer instead of by a sprite. A flat is shaded by its sector's light
level like every other surface, and the sector's light level IS these
fittings. Kill the lights over an aisle and the ceiling that was throwing
the light goes down with the aisle it was throwing it on.

A LIGHT IS STILL AN OBJECT, with no state and no sprite — the second such
thing in the game after a parked vehicle. It exists for its position, so
the relight pass knows where the sources are, and for its box, so a shot
or a fire can take it out. Ten health. Shoot it, or let a fire get under
it (the burn check is two-dimensional, so anything alight on the floor
below will eventually take out the light above it), and it throws sparks
that fall, pops, and the aisle goes dark for the rest of the level.

AND THE FIRE DOES MORE THAN DARKEN IT. Charring is a filter over pixels:
it can make a light fitting darker, and a darker picture of a light is
still a picture of a light — which is exactly what the first attempt
produced, a gutted black ceiling with four crisp lit panels in it. So the
charred ceiling has the fitting drawn again over it, dead: four broken
tube stubs with pieces missing, no diffuser at all (the glass is the first
thing off a fitting that has been in a fire), the flange's shadow back,
the ballast's scorch, and a few embers still in the tray. It is the one
texture in the game with a hand-drawn charred half, and it measures 0.17
against 0.33 for the burnt ceiling around it — darker than what it is set
in, which is what a dead recess is.

A sector's brightness is its own AMBIENT — emergency lighting, whatever
comes through the front — plus every working fitting that can see it. So
shooting one out genuinely takes light away, and a fire working its way
along a run of them puts an aisle out a section at a time. The reach test
is done near the ceiling on purpose: walls run floor to ceiling and stop
it, but a gondola is only 80 tall under a 352 ceiling, so light passes over
the shelves into the next aisle, which is what light does.

A sector is lit by the AVERAGE over sample points across its area, not by
the value at one place in it. The first version measured each lamp against
the nearest point of the sector's bounding box, which for a 600-unit aisle
is distance zero from every fitting along its length — so every sector
summed four or five lamps at full strength, clamped, and shooting them out
changed nothing anywhere. A long room is not close to a lamp; parts of it
are.

ONE MORE LIGHT, for the fire. Everything else is unlit, but a store that is
burning down and does not get brighter as it burns is not really burning. It
parks itself at the centre of mass of whatever is alight nearest you, and it
is added after the light is quantised, so the glow slides smoothly over the
banding instead of fighting it.


THE AIR, THE HOUR AND THE WEATHER
---------------------------------

SIGHT.txt is the plan and this is what was built of it. Four things,
and they are one thing: the sky, the fog, the hour and the weather.

THE FOG EXISTED AND WAS SWITCHED OFF. fogDensity sat at zero and only
js/fire.js turned it up, as smoke. What hid the far end of the world
was the far plane at sixteen thousand cutting the forest floor, with
the night panorama's own black ground showing through the cut — fine
at two in the morning against black, and not a system. It is two
terms now (worldShade in js/material.js): THE AIR, always on, that
every surface fades into with distance; and THE SMOKE after it, still
warm, still lit by the fire under it, still the fire's.

THE AIR IS A TEXEL OF THE SKY. Not a colour tuned to look like the
horizon: the world shader fetches the sky texture's horizon row in the
fragment's own azimuth — atan2(z, x) over a turn in the renderer's
axes, which was measured against three's SphereGeometry with the
mesh's x mirrored rather than derived, because a derivation that is
mirrored puts the dawn in the west — and fades toward that. A wall at
the end of the parade goes into precisely what is behind it and the
join is invisible because there is no join. At dawn the east end of
the lot is rose and the west end is blue-grey, and nobody wrote that
down. The sky sphere takes the smoke and not the air, which is a proof
and not a preference: the air IS the sky's horizon, so mixing the sky
toward the air is the identity. Both are in the test.

THE SKY IS BAKED IN THE PAGE, js/skyart.js, on the GPU, into a 4096 by
1024 equirect — four times the photograph's 1024 by 256 each way, in
two doublings and both at the user's request — for the hour and the
weather: a ramp, horizon to
zenith, and a ground below that starts as the horizon's own colour so
the far plane's cut has nothing to show; the sun as a disc with a
tight corona, and a glow along the horizon on its side that under a
dozen degrees of sun is the whole dawn; the moon two degrees across,
four times life size and the smallest thing that read as a moon at
the three texels a degree it was drawn for (it is over eleven now);
stars off a hash of the cell, one chunky pixel each, thinned by the
cosine of the elevation because an
equirect has as many texels round the zenith as round the horizon and
the sky does not, and a band across them with more in it; clouds of
value noise on a plane over your head, big overhead and
crowding to the horizon the way clouds do, drifting with the wind,
lit by the dawn from the side and by the town from below, and taking
the stars away; and the sodium glow of the town, low in the west.

THE SIZE IS ABOUT ONE NUMBER, which is a chunky pixel. At the picture
the game ships — 320 rows over a 72-degree view — a chunky pixel is
0.225 degrees tall, and a sky texel coarser than that is a sky visibly
blockier than the picture in front of it. The bake is 4:1 rather than
an equirect's usual 2:1, being mostly sky and a little ground, so its
two axes are not the same and both are worth writing down:

                    across            up and down
  1024 x 256        0.352 deg         0.703 deg
  2048 x 512        0.176             0.352
  4096 x 1024       0.088             0.176

The first doubling fixed the horizontal and left the VERTICAL still
coarser than a pixel is tall, and that is the axis the horizon, the
sun's lower limb and the cloud bases all lie along — which is where
the blockiness that was left came from. At 4096 both axes are finer
than a chunky pixel with room over.

AND TWO GRIDS DID NOT MOVE, which is the whole trick of doubling a
picture that is going to be dithered and shrunk. THE DITHER is worked
out on 1024 by 256 cells, now four texels square, because a checker
finer than a chunky pixel is a checker the post pass's averaging eats,
and what would be left is the post pass's own grain nailed to the
screen — the crawl a baked sky exists to prevent. AND A STAR IS ONE
CHUNKY PIXEL, so the stars are worked out on 2048 by 512 cells, the
grid they were already on: left on the fine grid a star would be a
quarter of a pixel, and a quarter-pixel star does not come out of the
post pass smaller and sharper, it comes out as a DIM SMUDGE, because
the averaging spreads it over the whole pixel at a quarter the
brightness. Read back out of the bake, the stars' share of the sky is
0.129 per cent against 0.130 before: the same count, the same size,
the same light, behind four times the paint.

IT IS CLAMPED TO WHAT THE MACHINE HAS. A render target wider than
MAX_TEXTURE_SIZE is one the driver refuses, and the answer to asking
anyway is a black sky on exactly the device that can least afford to
be debugged — so the baker asks the renderer, halves until it fits and
builds its shader for what it got. Both grids above are fractions of
the real size rather than numbers of texels, so a machine that can
only give 2048 gets the sky this had before: the same grain and the
same stars on half the paint. The bake costs 0.12ms against 0.04, at
most twice a second, and the picture is 16MB of texture against 4.

The fog, which reads the bake's horizon row, reads it half a texel up
in the bake's own row count rather than in a number typed next to it,
so it lands on the first row above the line whichever size the sky
came out.

IT IS STILL A PICTURE AND NOT A SHADER ON THE SPHERE, and that was
decided by one sentence in tools/bake-sky.mjs: baking is "what makes
the dither pattern sit still instead of crawling as you turn". The
post pass dithers in grid space, so a sky computed per fragment gets a
pattern nailed to the screen that crawls across the stars with every
mouse movement. A picture is dithered once, in its own texels, with
the same Bayer and the same palette snap the post pass uses — exported
from js/lofi.js so there is one definition — and the pattern is nailed
to the sky. It is re-baked when the hour has moved enough to show or
the cloud has drifted, at most twice a second; a quarter of a
megapixel, which is nothing.

THE HOUR IS ONE NUMBER, js/weather.js, and seven keyframes from ten at
night to eight in the morning are a table it interpolates: the three
sky colours, the sun's altitude and colour and how much it glows along
the horizon, the moon's place, the town's glow, how much starfield
survives, what the sky lights an outdoor surface to, and how dark
anything gets by distance. The judgement — what colour civil dawn is —
is in the table, in Javascript, where the headless test reads it; the
shader gets uniforms. The game is a night, so the clock is a night: it
starts at two in the morning, the hour the game was always set at, and
runs at four tenths of an hour a minute of play, which puts the sun up
in nine minutes. YOU HAVE UNTIL DAWN. Every hour the fire is worth
more of the light in the world and at first light the thing that made
you the only source of it is just weather. The clock stops at eight,
past sunrise, where the table is flat.

THE OUTDOOR LIGHT STOPPED BEING BAKED, which was the one piece of
engine work that was not optional. Game.relight sets every outdoor
sector's light to its ambient and js/mapgeo.js bakes that into a
vertex attribute, so a dawn would have meant rebuildStatic forty times
a night. The vertex already carries `sky` — how much of this surface's
light arrives from the sky — and that is exactly the weight: one
uniform lifts the vertex's own light toward the sky's, by that much.
Indoors it is the identity and two in the morning is the same two in
the morning; in the car park the dawn arrives in full; under the
canopy it arrives by half. A dawn is one uniform write a frame and no
rebuild at all.

THE PALETTE GOT A SKY RAMP. It was exactly full, fourteen ramps
summing to 256, and a dawn fills half the frame with a gradient no
ramp ran through — night blue, violet, rose, cold gold, the pale blue
of a morning. The first screenshot was that gradient snapped into blue
and pink and dithered into crosshatch. Twenty entries came out of
grey, cyan, purple and pink, and the test that says whether they are
enough is the one that snaps every colour in the table and measures
the miss.

THE RAMPS ARE THE MATERIALS AND THE PALETTE IS THE BOX OF CRAYONS, and
they were the same thing for most of this project's life: the 256 WERE
the fifteen ramps laid end to end, and ramp(key, t) handed back a
palette entry BY INDEX. That is the right way round for one palette and
it is the reason there could only ever be one — swap the box and every
index into it means a different colour, so every texture in the game
comes out SCRAMBLED rather than recoloured.

They are two things now, and the split is three lines: RAMP_RGB is what
a material IS, fifteen ramps of arithmetic computed once and never
changing, and what ramp(key, t) answers with; the palette is what the
machine can show. Painting picks the material, snapping puts it in the
box.

AND THEN THERE ARE TWO PALETTES, which is the part worth reading
carefully, because they answer different questions and the first attempt
had them the wrong way round.

  THE ART PALETTE is what a picture is PAINTED in. It is the fifteen
  ramps, it is what every texture generator and every sprite decoder
  reaches for, and it is what js/art-data.js's indices mean. It never
  changed for most of this project's life, and this chapter said so in
  those words. It is a setting now — see AND THEN A SECOND BOX TO PAINT
  IN below — and the thing that made that possible is the thing this
  chapter is about: the ramps and the box were separated, so swapping
  either one no longer scrambles the other.

  THE DISPLAY PALETTE is what the SCREEN can hold. The post pass
  dithers the finished frame and snaps it through a lookup cube built
  from this one, the sky bakes through the same cube, and this is the
  one the setting swaps. It carries the dither's grid as well as its
  colours, because how far the dither has to reach is a fact about the
  box — see AND THE DITHER'S GRID HAD TO GO WITH IT.

THAT WAY ROUND ON PURPOSE, at the user's request, and it is the
difference between a good picture and a noisy one. Painting the textures
in the small box as well was the first thing built and it was WORSE: a
texture dithered at 64 texels and then dithered again at grid resolution
is not twice the texture, it is noise, and the crosshatch of the first
dither shows up as a pattern moving over the wall as you walk. Leave the
art at full colour and the ordered dither carries it down to the
hardware box ONCE, at the last moment, at the resolution the screen
actually is. Same box, better picture.

IT IS ALSO WHY THE SWAP IS FAST. There is nothing to repaint: the
setting rebuilds the lookup cube in place — with the new box's dither
grid alongside it — and bakes the sky again, because the sky is a
picture baked THROUGH that cube and is otherwise left in the old box.
Under sixty milliseconds, measured, against the eight hundred and
thirty-eight the re-bake version cost. applyPalette in js/main.js is
three lines now and the third is the sky.

THE SECOND BOX IS THE UZEBOX'S, which the user sent as 256 lines of hex.
It is not a mood board, it is a piece of hardware: an AVR driving a
picture straight out of its pins through a resistor ladder, three bits
of red, three of green and TWO OF BLUE, which is 8 x 8 x 4 and is
exactly 256. It is generated in js/palette.js rather than pasted in,
because 256 lines of hex is a table nobody can check and three loops is
a table that cannot be wrong; art/uzebox.hex is kept as the file it is
checked against, entry for entry.

WHAT IT DOES, MEASURED: the 256 the ramps make land on 81 distinct
entries of that box, twenty-six units of 255 away on average, and the
sky ramp's twenty land on thirteen. Two bits of blue is the whole story
— a night sky that is a gradient here is four flat bands there, and the
dither is what stands between those bands and the eye. That is not a
defect in the palette, it is what the hardware was, and it is the reason
this is a SETTING and not a replacement.

AND THE DITHER'S GRID HAD TO GO WITH IT, which is the part that was
wrong in the first build and is the difference between the two
screenshots. The Bayer threshold moves a pixel half a step of an RGB
grid before the snap, and the shipped grid was a sixteenth of a channel
— sixteen units. Four levels of blue are gaps of EIGHTY-FIVE. A
sixteen-unit wobble at an eighty-five-unit gap does not dither it: the
picture comes out flat, then a narrow band of checker where the two
nearest entries happen to fall within a sixteenth of each other, then
flat again, which is banding with a seam through it. The night sky came
out as a black and olive crosshatch, because the nearest thing that box
has to a dark blue is a tie between black and a dark yellow-green, and
the dither could not reach the blue that would have broken the tie.

SO THE GRID IS A PROPERTY OF THE BOX and travels with it: 16 16 16 for
the ramps, which is a look and was chosen by hand, and 7 7 3 for the
Uzebox, which is not a look — it is that box's own gaps, eight levels
being seven of them and four being three. At 7 7 3 the whole gap
checkers, the sky is dark BLUE again and the dawn is a gradient. It
changed forty per cent of the frame in that box and nothing at all in
the default, which is the shape a change like this should have.

THE SKY IS THE ONE THING THAT HAS TO BE TOLD. Everything else in the
frame arrives at the post pass as full-colour art and gets snapped on
the way out; the sky arrives already snapped, because it is baked to a
texture once an hour of game time rather than shaded per pixel, and the
bake does its own dither-and-snap against a palette handed to it at
start-up. So buildLutAtlas still takes an explicit palette even though
nothing passes one in the normal path — the sky's own test wants to ask
about a box that is not the one in use — and the pipeline rewrites its
cube IN PLACE rather than making a new texture, because the sky baker
was handed that exact texture object when the game booted and a new one
would leave the two drifting apart with only the sky in the old box.

AND THEN A SECOND BOX TO PAINT IN
---------------------------------

At the user's request, and asked for as a TEST THEY COULD UNDO: remap
the textures and the palette to muted, earthy tones. Which is the right
shape for it: a repository is a bad place to keep an experiment, and
this game already had the machinery to make it a setting instead.

WHAT IT IS. Fifteen more ramps in js/palette.js, with the same keys, the
same lengths and the same order as the fifteen the game was drawn in.
The greys go warm stone, the greens go sage and dried grass, the blues
go slate, cyan goes verdigris, yellow goes ochre, purple goes heather,
pink goes clay. The blacks go BROWN — a shadow in the stock box is
[6,7,11], a shadow full of skylight, and in this one it is [16,14,12], a
shadow full of dust. And nothing reaches white: the top of every ramp
comes down from the 248-252 the stock box runs to, into the 190s and
220s, and warms on the way, because the single loudest thing about a
faded picture is that its highlights are not white.

Measured over the whole 256: the saturation goes from 0.281 to 0.219 and
the brightest thing in the box from 252 to 238.

THE THREE THAT WERE ALREADY EARTH HARDLY MOVE, and that is the argument
for the box rather than a coincidence. Weighted 3:6:1 across R:G:B — the
eye's own weighting, the same one the palette snaps with — cyan travels
25, yellow 21, red 21, green 18, and brown travels 5, rust 7, flesh 8.
Brown, rust and flesh were the answer before the question was asked.

AND THE FIRE DOES NOT MUTE. It travels 11, less than any of the four
most coloured ramps in the box, and it keeps its route exactly: the same
seven stops in the same places, black to dark red to blood to ember to
orange to yellow to white heat. What comes off it is the neon — the
white heat down from [255,255,226] to a warm bone — and nothing else,
because the fire is the subject of this game and the one thing in the
frame that is supposed to be the brightest thing in the frame. Muting it
would be muting the point. THE EMBER RAMP is not in the swap at all for
the same reason: it is what everything still glowing after the flame has
gone is lit by, and it stays the colour a coal is.

THE SAME FIFTEEN IS THE WHOLE TRICK, and it is a constraint rather than
a convenience. RAMP[key] lands at the same index in both boxes, so entry
n of the palette is the same MATERIAL in both — which means the two
photographed pictures in art/, which are kept as palette INDICES in
js/art-data.js and would otherwise have to go back through
tools/bake-art.mjs, come out RECOLOURED rather than scrambled. Change an
`n` and that stops being true silently, so the suite holds the two lists
against each other, ramp for ramp.

AND IT IS FILLED IN PLACE AND NEVER REPLACED. Half the game is holding
that array — PALETTE is it, the default display box is it, the art
decoder indexes it — and a module that captured it at load time would
keep the old colours for ever if setArtPalette handed back a new one. So
every entry is written THROUGH and everybody holding it sees the new box
on the next pixel they ask for. The snap cache goes with it, which is
not a nicety: every answer in it is an index into a palette that no
longer holds those colours, and the first texture repainted through a
stale one would come out in the box it was supposed to be leaving.

WHAT HAS TO BE MADE AGAIN is more than the display palette needed, and
that is the difference between the two settings. The display palette
changes what the screen HOLDS and there is nothing to repaint; this one
changes what the art IS. So: the textures, repainted into the same
three.js texture objects every material in the scene is already holding;
the sprites, and then THE PHOTOGRAPHS LAID OVER THEM AGAIN, because a
repaint puts every stand-in back and the order is what makes a face a
face; the weapons the HUD draws; and then the lookup cube and the sky,
exactly as the display setting already does them. About a second, once,
on a button nobody presses in a firefight — and the way back is the same
button.

WHAT IS NOT MADE AGAIN, on purpose: the particle atlases, the GLB
models and the photographs themselves. All three are snapped through the
cube at the last moment like everything else in the frame, so they land
in the new box anyway — the same argument the Uzebox palette already
makes. The difference between that and a repaint is that a repaint DRAWS
in the new box instead of being quantised into it, and drawing is what
fifteen ramps make possible and a photograph does not.

AND THEN IT BECAME THE DEFAULT, at the user's request, which is the
happiest way for a test you can undo to end. TONE: EARTH | AS DRAWN, in
the pause menu, remembered, and applied BEFORE anything is painted when
the game starts — a game that boots in a box should not spend three
quarters of a second at the loading screen painting itself twice.

TWO THINGS HAD TO BE SAID OUT LOUD when the default moved, and both of
them are the kind that would otherwise have gone wrong quietly.

THE ART BAKE PINS THE STOCK BOX BY NAME. tools/bake-art.mjs writes the
two photographs in art/ as palette INDICES, and an index is only
meaningful because both boxes have the same fifteen ramps in the same
order. But which box to QUANTISE against is a different question with
one right answer: the fuller one. A photograph snapped into a muted box
and then recoloured is a photograph that has been through two
quantisations. So the tool asks for `stock` outright rather than taking
whatever is current — which also keeps js/art-data.js byte-identical
when the default tone moves, and that matters, because CI re-bakes it
and fails on a diff.

AND A SAVED `tone` IS AN INDEX. TONE_SET was reordered to put the new
default first, so a saved 0 used to mean AS DRAWN and now means EARTH —
right for anybody who never touched it, wrong for anybody who did. The
preferences version is bumped and a saved tone dropped rather than
reinterpreted. WHILE DOING THAT the reset itself got narrower: it used
to throw away the same four picture settings on ANY version bump, so
saying one thing about the tone would have taken away a picture somebody
had spent a while dialling in. Each line of it says which version it
belongs to now.

AND THE HAZE THE FIRE MAKES, ON A SWITCH
----------------------------------------

At the user's request. It is a debug switch and not a picture setting,
because what it turns off is not an effect: a town alight from end to
end really does put a lid over itself, and that lid is why the last four
screenshots of this game have all been orange.

WHAT IT TAKES AWAY is the two things a fire does to the AIR. The smoke
sky — the brown lid that reddens the sun, kills the stars, dims the
light and pulls the visible distance in from a clear night's fourteen
thousand units to under three. And the warm fog, the near-field murk
that fills the room you are standing in. Measured, with the town
properly alight: smoke 0.95 and fog 0.62 and three thousand units of
seeing, against 0 and 0 and fourteen thousand with the switch off.

WHAT IT LEAVES ALONE is everything that is the fire ITSELF — the flames,
the embers, the sparks, the light they throw, the charring, and the
ambient that lifts as the building goes so you can still find the way
out of a gutted store. Those last two are checked: the minimum light and
the global light do not move by a thousandth when the haze goes.

IT SNAPS RATHER THAN EASING. The smoke takes forty seconds to come in
and a hundred and fifty to clear, which is exactly right for a sky and
useless for a switch you are flicking to compare two frames — so turning
it off is immediate. Turning it back on is not: it comes back in the way
a sky does, by degrees, because that is the thing itself again.

DEBUG: FIRE HAZE, in the pause menu with the other two, on by default,
remembered.


THE POSITRON SNIPER LANCE
-------------------------

THE FIFTH WEAPON, at the user's request, and the first one in this game
that is not a trigger you pull. It is a trigger you HOLD.

Vaportrash's WZBR-1 Positron Sniper Lance, brought in as it stands and
stripped by tools/prep-model.mjs from 8.7 megabytes to 4.4 — the normal
map, the metal-rough map, four sets of UVs and a tangent for a normal
map that is no longer there. Slot 5, or the wheel, or SWAP. Two and a
half metres of gun, half again the length of anything else in the rack,
held further out than anything else for a reason that is not vanity: the
back of it is where the SCREEN is.

THE MODEL CARRIES ITS OWN ANSWERS, the way the minigun did, and not as
marker spheres this time but as NAMED MESHES. Four meshes on three
materials:

  wzbr_mat                     seventy thousand vertices of receiver and
                               barrel on one painted 1024-square sheet
  optics_2 / optics_mat        a fifty-millimetre lens up front, painted
                               flat green
  dynamic_display_surface_1 /  a panel eighty millimetres across on the
  dynamic_display_surface_mat  rear deck, facing straight back at
                               whoever is holding it, painted flat
                               near-black

Nobody names a node `dynamic_display_surface_1` by accident. The whole
of js/scope.js is the answer to that name.


THE TRIGGER IS A DURATION
-------------------------

Three seconds is a stage, five is two, seven is three. It fires on the
RELEASE, and — at the user's request — ONLY FROM THE THIRD MARK. Let go
at four seconds and nothing leaves the muzzle: the cell is not spent,
the coil fizzles down, and you have cancelled a charge. Letting go early
is one of the two ways to cancel one; the other is holding it past the
window at the top, which vents it for you.

THIS IS A DIFFERENT WEAPON FROM THE ONE THE FIRST CUT SHIPPED. Firing at
whatever stage was reached made the stages a menu — three seconds for a
small shot, seven for a big one, and a player in a hurry never waits.
Firing only at red makes them a COUNTDOWN. There is one shot this gun
takes and it costs you seven seconds of standing still at a third of a
walk with a light on the end of your barrel that every shopper in the
street can see. The dial has to go round before anything happens, which
is why the dial is on the gun. FIRE_AT in js/player.js is the whole
rule, and it is CHARGE_STAGES.length rather than a 3 typed in, so a
fourth stage would move the bar with it.

AND AT THE TOP THERE IS A WINDOW. Five seconds at the third mark and
then the coil vents for you: the charge goes, the shot does not happen,
the cell is not spent, and you start again. Between those two states
there was a third — forty seconds of overcharge that ended with the gun
killing you — and it is gone at the user's request. See DIALLED BACK,
below, which is where the whole of that lives now.

A trigger held through a vent still does not start another charge — you
have to let go and press again.

WHILE IT WINDS you keep a third of a walk and cannot run. That is not in
the user's ask and it is the number that makes the three stages mean
something: a seven-second charge you can sprint through is a trigger you
hold all the time. WHILE THE BEAM IS OUT you cannot move at all, which
is, and the momentum is spent at the moment of firing rather than
ignored for the length of the discharge, so you stop where you fired
from rather than sliding to a halt under a beam that is already lit. The
HEAD is free, which it did not used to be: the sweep was clamped to a
fifth of its rate while the column chased the barrel, and the column
does not chase any more. See THE LINE IS NAILED DOWN AT THE TRIGGER.

AND IT DOES NOT COOK. A coil that heated as it wound, glowed on the
chassis and refused its own trigger over a threshold was the right
machinery for a weapon whose limit was how much you dared ask of it, and
at the user's request this is a precise weapon whose limit is somewhere
else. The CELL is where: it holds four and fills itself one every
twenty-five seconds, which is the slowest magazine in the game and
should be — a full cell is four lines drawn through the town, and at
seven seconds of charge apiece you will think about all four.


DIALLED BACK: A SNIPER AND NOT AN ARMAGEDDON
--------------------------------------------

At the user's request: "lets dial the positron lance way back, no
overload, no heat, focus on precise sniping as opposed to armageddon."

Three things went, and it is worth naming them because the rest of this
chapter used to be about them.

THE OVERCHARGE, IN ITS ENTIRETY. Holding at red used to wind a second
clock: forty seconds, a ladder of CAPACITOR warnings in the corner, a
screen that tore and dropped rows harder as it climbed, and at the end
of it the coil let go where you were standing and killed you — a blast
sixteen hundred units across, eight beam-holes blown through the
buildings round you as a star, and a third-person camera that pulled
out of the body to watch. Letting go DURING it fired an absurd version
of the shot: nearly three times as wide, three and a half times the
bite, twice as long, and a shove that threw you three hundred units
backwards down the street on your back. None of that is here. There is
no OVERCHARGE_TICS, no blowUp, no OVER_WIDE, no death camera, and
nothing the gun can do to the person holding it.

THE HEAT, IN ITS ENTIRETY. The coil cooked as it wound; the whole
chassis glowed with it from the middle out on GUN_FRAG's second gradient
mode; the glass on the back glowed at half of that; and over a threshold
the gun refused its own trigger until it had cooled back under a lower
one. There is no lanceHeat, no lanceHot, no LANCE_HOT, no CHARGE_HEAT
and no VENT_HEAT. The gun rack's LANCE entry has no `heat` at all, so
the minigun is the only weapon in the game that cooks, and the shader's
middle-out mode is left in place with nothing asking for it — it is one
branch behind `if (heat > 0.001)`, it is correct, and the next gun that
heats from its middle will find it already written.

WHAT LIMITS THE WEAPON NOW is the thing that always should have: it
holds four cells and they come back one every twenty-five seconds, the
slowest magazine in the game. A charge takes seven seconds and you get
four of them.

AND AT THE TOP THERE IS A WINDOW AGAIN. Five seconds — HOLD_TICS — and
then the coil vents: the charge goes, the shot does not happen, the cell
is not spent, and you start the seven seconds over. It costs nothing but
the time. The first cut had three seconds of this, the overcharge
replaced it with forty and an explosion, and five is what it is now
because a sniper is ALLOWED to wait for the shot — five seconds is long
enough to track somebody the length of a street or let a van clear the
line, and not long enough to hold the trigger down while you go looking.

The gun's screen draws the window on the ring the heat used to have, and
draws it DRAINING, because the question is how long you have left rather
than how long you have had. In the last quarter of it the middle of the
reticle blinks red as well: a ring that is nearly empty is a ring that
is nearly not there, and the middle of the reticle is the one part of
that panel the eye is already on while you are aiming.


A COLUMN NARROWER THAN A PERSON
-------------------------------

The armageddon was never one feature. It was in the numbers, and this is
all of them:

                       was          is
  radius (stage 3)     130          24
  beam seconds         3, 4, 5      0.6, 0.9, 1.4
  structure a pass     1.30         0.0105
  heat a tic           470          110
  light peak / range   1.00 / 1200  0.55 / 440
  shake peak / hum     1.00 / 0.34  0.62 / 0.05
  shake settle         18 tics      7 tics
  afterglow            1.6s         0.9s
  heard at             2400 units   1100 units

THE RADIUS IS THE ONE THAT MATTERS. A hundred and thirty is a column
eight people wide that took the whole front of a house at once; you did
not aim it, you pointed it, and whatever was within four metres of what
you meant went with the thing you meant. Twenty-four is forty-eight
across — one and a half people rather than eight — so it takes the
person the crosshair was on and at most a shoulder of whoever is pressed
against them.

AND IT CANNOT GO NARROWER, which is the part worth writing down, because
it looks like a taste decision and is not. The beam's radius is also the
radius of the hole it bores through every wall it crosses, and the
player is thirty-two units across. At forty-eight there are eight units
of clearance either side and you can walk through your own hole, which
is a thing this game already promises three sections above this one. At
thirty you could not. Twenty-four is a floor and the reason is
collision.

NO SINGLE SHOT CAN BRING A BUILDING DOWN ANY MORE, at any stage, however
squarely it is aimed. The old table took 1.30 of a region's integrity
per pass with fifty-odd passes left to run, so every discharge levelled
whatever it was fired through and the hole in the front of the building
was academic — the building followed it down a quarter of a second
later. The ceiling now is 0.50 for a whole stage-three discharge, and
the measured figure against the town is 0.34, so it is THREE shots. You
hold four cells. Levelling a building costs three quarters of everything
you have and twenty-one seconds of charging: a decision rather than a
side effect of shooting at a man standing in front of it.

(The ceiling and the measured figure differ for a reason worth knowing
if you ever retune this. FireSystem.damageLine bites
`amount * (1 - |t| / radius)` and keeps the largest bite any sample of a
region took, so only a region the column's dead centre passes through
takes the whole of it. The suite checks the CEILING, because that is
what can be proved from the constants and it is also the half that
matters: under 1.0 means never in one shot.)

MIND PASS_EVERY IF YOU DO RETUNE IT. BEAM_STRUCTURE is per PASS and the
caller multiplies by PASS_EVERY, so a stage-three discharge is 49 tics =
16 passes x 3 x 0.0105. The first cut of the dialled-back table forgot
that factor, came out at 1.34, and levelled a house in one shot anyway —
which was the exact thing it was written to stop.

THE HOLE ITSELF IS UNTOUCHED. Punching a clean bore through every wall
on the line is the PRECISE part of this weapon and none of it changed:
the same breaches.cut, the same debris tunnel round the rim, the same
burning. What changed is that the wall the hole is in stays up.


THE LINE IS NAILED DOWN AT THE TRIGGER
--------------------------------------

There is a real geometry problem here and the fix used to be the
opposite of what it is now.

A beam fired from the gun in your hands, along the line you are looking
down, is seen END-ON. Always. However you turn, the column turns with
you and what is on screen is its cross-section: a bright disc in the
middle of the frame. That is unavoidable and it is what the first three
screenshots of this weapon were — a glowing blob over a lawn, with none
of the length that is the entire point of it.

THE FIRST ANSWER WAS INERTIA. The barrel said where the column wanted to
be and the column chased it at a time constant of a third of a second,
so while you swept it trailed about twenty degrees and you saw its side.
It worked, and it cost the thing this weapon is now for: the damage
followed the DRAWN column rather than the crosshair, so where a shot
landed depended on how your wrist happened to be moving as you let go.
You could not aim it. You could point it and lean.

THE SECOND ANSWER IS BETTER AT BOTH JOBS. The line — origin and
direction both — is taken once, in _aim, called from fire() and nowhere
else, and never moves again. So the shot goes exactly where the
crosshair was, which is the whole of "precise"; and the end-on problem
solves itself more completely than the lag ever solved it, because the
moment you turn your head AT ALL the column is no longer in front of
you. It is a fixed line in the world and you are looking across it. Turn
ninety degrees and you see the entire eight thousand units in profile.

AND THE SWEEP CLAMP WENT WITH IT. Turning used to be cut to a fifth of
its rate while the beam was out, because a free head on a chasing column
meant one shot could take all four sides of a junction. Nothing is left
for that clamp to protect, and it was costing the one thing the shot is
for: turning to look along the line it left. The feet are still nailed
down. The head is free.

THE SHAKE CAME DOWN TO MATCH. A kick rather than a rumble: nearly all of
it inside the first fifth of a second and then a trace, because the
thing worth looking at is where the shot went, and this weapon is no
longer aimed WHILE it fires.


AND THE GUN SAYS WHAT A SHOT YOU CANNOT SEE WENT THROUGH
--------------------------------------------------------

The toast stack outlived the feature it was built for. It was made for
the overcharge's four warnings and a fifth line as the coil killed you,
all of which had been going through setBigMessage — thirty-point type
across the middle of the screen, one at a time, each wiping the one
before it, in the way at exactly the moment you were trying to aim, and
landing on top of the end-of-night card.

The problem it solves is WORSE for the dialled-back weapon, not better.
This gun fires along eight thousand units of street, through whatever is
standing in the way, and almost everything it does happens somewhere you
cannot see from where you fired it. A clean kill at range and a clean
miss at range look identical from the muzzle: a bright column, and then
nothing. So the gun says two things, in small type, bottom left:

  COIL VENTED                    the window ran out, here is why your
                                 seven seconds just evaporated
  2 DOWN  ·  39 THROUGH          what the last shot did, once, and only
                                 when it did something

A shot that hit nobody and went through nothing says nothing, which is
itself the answer to "did I get him".

THE TALLY IS A MAX AND NOT A SUM, and this only started mattering when
the number began being shown to a player rather than to the tests.
breaches.cut returns how many walls it opened on THAT pass, and the line
does not move any more, so every pass after the first re-opens the same
ones. A shot through 39 walls accumulated to 624 over sixteen passes and
the gun cheerfully said so. The most any one pass opened IS the number
of walls the line crosses, because the first pass opens all of them.


THE BEAM
--------

IT IS NOT A LASER. A laser is a line you draw to a hit point and it
stops at the first thing it touches. This is a COLUMN half a metre to a
metre and a half across drawn from the muzzle to the far side of the map
— eight thousand two hundred units, which crosses the town and keeps
going — and it does not stop at anything, because nothing SOFT it
touches is still there afterwards. There is no hit point. The whole
segment is the hit.

Every tic, for the second and a half it is out, it does four things:

  the bodies      everything soft inside the column, every tic, for
                  enough that there is no survivable stage
  the buildings   integrity off every region the column passes through,
                  on a slower clock
  the fire        heat and accelerant the whole length, store grid and
                  woodland both, so what the beam did not finish burns
  the picture     sixteen sample points a tic, moved along the line each
                  tic and scattered ACROSS the column rather than along
                  its axis, so the discharge lays a continuous stem of
                  fire up the whole length

THE BUILDINGS ARE ON A SLOWER CLOCK THAN THE BODIES and it is worth
saying why. Taking a region down is a walk over the fire grid, and a
stage-three column is a metre and a half across and eight thousand long:
the box that bounds it is a good part of the town. Doing that
thirty-five times a second for the whole discharge is fifty sweeps of a
grid to answer a question whose answer changes about twice. Every third tic with the bite multiplied by three is the same
building coming down for a third of the arithmetic. Bodies are a flat
loop over the actor list and cost nothing, so they run every tic, where
the player can see them.

THE WALK ITSELF LIVES IN js/fire.js, next to the blast's, because the
grid belongs to the fire: FireSystem.damageLine is the third way to
bring a building down and the first one that is a LINE. It walks in the
line's own frame — how far along the ground track a cell lies, and how
far to the side of it — which is what lets it answer the question a
circle never has to: how HIGH the beam is over that cell. A shot fired
level from the eye is through ground floors for its whole length; one
fired up the road at ten degrees is through the bedrooms by the end of
the street and over the roofs after that. And it takes EVERY STOREY the
column touches, not the one it is aimed at, because at the widest stage
the column is taller than a storey is.


AND IT IS A TUBE
----------------

The obvious way to draw a beam is the way js/tracers.js draws a round: a
quad spread sideways along the axis that is across both the line and the
line to the eye, so it faces you however you stand. That is right for a
tracer and catastrophically wrong for this one, because of WHO IS
LOOKING. A tracer is something you watch go past. A beam is something
you are FIRING, which means the eye is at one end of it looking along
it — and a view-facing quad seen exactly end-on is a line one pixel
wide. The most important beam in the game would be invisible to the only
person who ever sees it.

So it is real geometry: a tube of twelve sides and twenty-eight rings,
rebuilt every frame around the axis the barrel is on THAT FRAME. Looking
down a tube shows you the inside of a tube, which is exactly the shot —
a ring of light receding to a point — and looking across one shows you a
column.

THREE OF THEM, NESTED, because a column of light is not one colour: a
white core lit through its whole face, a yellow-white body, and a halo
in the lance's own lens green lit only at its SILHOUETTE. Fresnel
against the view direction is the entire difference between a rod and a
glow and it is two lines of shader. With rings travelling out of the
muzzle, because a column with nothing moving along it has no speed and
no direction, and five seconds of a static glowing pipe reads as a prop.
All of it additive, none of it writing depth, one draw call.

THE NECK IS IN WORLD UNITS AND NOT IN A FRACTION, and the first cut of
it was not. It flared the column over the first five per cent of its
length — four hundred units, which sounded reasonable — and the first
screenshot of a stage-three discharge was a white rectangle with a gun
in the corner of it. The column is born at the muzzle, about forty-six
units in front of the player; at the third stage it is a hundred and
thirty units in radius. Forty-six is less than a hundred and thirty. The
player was standing INSIDE the first section of their own beam, looking
at the inside of a double-sided additive tube from a few centimetres
away. It opens out over six hundred units of real distance now and is
not drawn at all over the first three hundred; what covers the join is
the muzzle bloom, which is particles and was going to be there anyway,
because a beam leaves a gun in a ball of light.


WHAT IT DOES TO THE PICTURE
---------------------------

THE SCREEN SHAKES, at the user's request, and it is the one thing in
this game that moves the eye while the player is standing still. Off the
wall clock and not the tic — a shake is something the PICTURE does, and
at a tic it would step thirty-five times a second whatever the frame
rate is, which is a judder rather than a shudder. Four sines at rates
that do not divide into each other, so it never repeats inside the five
seconds a discharge lasts. Everything in the first half second and a hum
for the rest: a discharge you cannot aim through for five seconds wastes
its own best feature. It is added to the EYE and not to the player, so
it never walks your aim off the street you picked.

AND THE WORLD HAS A SECOND LIGHT NOW, which the README has said for a
year it does not need. It did not, for fire: a burning aisle is one glow
because you never see two fires as two sources. It is not true of this.
A point light at the muzzle would put a bright spot on the wall behind
you and leave the street the beam is crossing dark, which is backwards.
So the second light is a SEGMENT — a start, a direction, a length and a
radius — and every fragment measures its distance to the nearest point
on the LINE. A person standing beside the column a hundred metres away
is lit as hard as the wall behind the muzzle, because they are as near
the light.

IT IS DIFFERENTIAL AND RANDOMISED, at the user's request, and that is
the part that makes it read as a discharge rather than as a lamp: the
flicker's rate AND its phase are hashed off the fragment's own world
position, so two objects either side of the column flicker differently
and neither of them flickers with the frame. What you get is a street
where every surface is being lit by the same thing and none of them
agrees about it.

AND IT OUTLIVES THE BEAM. The axis is left exactly where the last tic of
the column was and the intensity falls off over a second and a half, so
the street stays lit by a thing that has already gone — the after-image
of the shot.

IT WAS ALL FOUR TIMES TOO BRIGHT TO BEGIN WITH. The column, the wash on
the readout, the bloom and the light were each bright enough on their
own, and together they were a white rectangle. The column is the one
that should be blinding. A street lit past white has stopped being a
street.


THE SCREEN ON THE BACK OF THE GUN
---------------------------------

js/scope.js. What is on it is the WORLD, live, through a second camera
at the player's own eye with a narrow field of view — a camera-to-texture
feed and not a painted picture — with round gauges over it and a reticle
in the middle. It is a sniper scope that happens to be a monitor, which
is what a lance with a flat panel where the optics should be IS.

THE FEED IS ITS OWN RENDER, because a zoomed picture is a DIFFERENT
picture and not a crop: twelve times the magnification is twelve times
fewer degrees across the same texels, and there is no way to get that
out of a frame drawn at seventy-two except by drawing it again. So there
is a second perspective camera parked at the world camera's position
with the world camera's rotation and a field of view divided by the
magnification, and one more render of THE SAME SCENE into a
256-square target.

The same scene is the whole trick. Nothing is duplicated and nothing is
kept in sync: the crowd, the fire, the town and the sky are whatever the
frame already made them. Everything the game culls — the portal flood,
the distance cuts in Actor.render, the geometry LOD — was computed from
the same standpoint the scope is looking from, so a narrower camera at
that point can only ever want a SUBSET of what is already there. There
is no case where the scope wants something the frame threw away.

It is small and slow on purpose: 256 texels square, at most every other
frame, and never at all with the lance out of your hands. A screen
eighty millimetres across on a gun held at arm's length is forty chunky
pixels once the lo-fi pass has had it, and a feed that updates thirty
times a second on it is indistinguishable from one that updates sixty.

THE UVs ARE NOT THE FILE'S. The panel's own live in a twenty-six
thousandth of the sheet — 0.495 to 0.521 across, 0.704 to 0.722 up —
because in the original it is one flat dark patch of an atlas and needs
no more; mapping a screen through them would sample one texel. So the
screen makes its own out of the mesh's LOCAL POSITION, which it can
because the panel is planar: all thirteen of its vertices sit at
z = -0.1694, so x and y across its own bounding box ARE the two axes of
the picture. The box is measured off the geometry the file shipped
rather than off a number written in the game, so a re-export that moves
the panel moves the picture with it. And u is FLIPPED, because every
model is turned half a circle about y so its barrel points away from the
eye, and a half turn about y sends model +x to view -x: un-flipped, the
scope feed is a mirror. It was, the first time, and a checkerboard with
a red border said so.

THE GAUGES ARE FOUR THINGS, and that is a rewrite. The panel is forty
chunky pixels across, and the first cut had two arc gauges with their
own labels, a third round dial, a range readout and a four-rung ladder
on the reticle. At forty pixels all of it was one green smear. What is
there now:

  the outer ring   the charge, three quarters of a turn, thick enough to
                   read as a bar, with the three stage marks cut THROUGH
                   it in the background colour — a line drawn over a lit
                   arc at this size is a lit arc
  the inner ring   the window at the top of the charge, DRAINING,
                   concentric inside it and going the same way, so the
                   two are one instrument read from the outside in: the
                   charge fills, then the window empties, and if the
                   second runs out the first goes with it. It was the
                   coil's temperature until the heat went — a gauge you
                   could do nothing about, replaced by one you act on
  four pips        the cell, because it holds four and four dots are
                   legible at a size an arc is not
  the reticle      a cross with a gap, and a box round the middle that
                   blinks while the beam is out

and one character, the stage, with the zoom step in small type below the
reticle. In the last quarter of the window the middle of the reticle
blinks red, which is all that is left of a bar across the bottom saying
CAPACITOR and a red flash over the whole panel — those went with the
overcharge. Everything is inside the bezel, and the bezel is a SQUARE
one:
the glass goes dark past max(|x|, |y|) * 2 > 0.94 off the middle, so
what matters is the greater of the two axes and not the distance from
the centre. That was the bug: the charge ring, the biggest thing on the
screen and the one the whole weapon is about, was drawn at 0.44 with a
rim of its own on top, inside the part that had already been faded out.
The gauge was not on the gauge. The first repair for it counted the
`N * 0.xx` numbers in the source and compared them against a threshold
typed into the suite, which went stale the moment the warning bar
arrived — a Y COORDINATE of 0.905 and a RADIUS of 0.905 are not the same
distance from the middle. The suite now DRAWS the dial into a context
that records where the ink went and measures the extent the way the
shader measures it: 0.907 of 0.94 at the widest, with the deliberate
full-panel fills exempt.

The whole thing is drawn in the lens's own green — the model says the
optics are (0.344, 0.800, 0.000) and the monitor is that, because a
screen that does not match its own glass is two parts from two guns —
with scan lines, a two per cent barrel bow, a slow roll, and static that
climbs with the heat. It imports nothing from js/palette.js: it is a
screen and not a painting, and the earth box must not mute it.

THE ZOOM IS NOT A ZOOM. It is a press — the right mouse button, Z or C,
or B on a pad, and on a phone the AIM button and the magnification (see
ON A PHONE) — and what it does, at the user's request, is BRING THE
GUN TO YOUR EYE. The first cut magnified: 1x, 4x, 12x on the panel with
the main view narrowing to match, and twelve times on a forty-pixel
screen is a smear. "Less zoom and more just looking through the gun
scope" was the note, and it is the better weapon — you are not operating
a telescope, you are putting your face against the back of a rifle.

So the weapon MOVES. GUNS.LANCE carries a second hold beside its first
one — `aim: {pos, rot, out}` — and pressing zoom blends the gun from one
to the other: up, inboard, and pulled in until the panel on its rear
deck is a hand's breadth from the eye and square in the middle of the
frame. The turn cancels VIEW's own cant, so you are looking AT the
screen rather than across it. Bob and sway damp to an eighth on the way
in, because a screen that close magnifies every wobble in the hold.

THOSE FOUR NUMBERS WERE SOLVED AND NOT NUDGED. With the panel's own
corners projected through the weapon camera, both its position and its
size on screen go exactly as 1/d, and d is linear in `out` — measured
d = 0.330*out - 0.481 over four settings, and the panel's height in clip
units is 0.1333/d to four places. So out = 1.80 puts the screen 0.113
from the eye and 1.18 clip units tall, which is 59% of the picture's
height and about square. Position is linear in pos at a fixed out (the
push is along the eye ray, so it cannot change d), which makes centring
a two-line solve: 9.18 clip units per unit of pos.x, 14.71 per unit of
pos.y. pw/place.mjs is the probe that measured it.

THE STEPS ARE THREE and the gun comes up in two of them: hip, then 82%
of the way in at 2.1x, then all the way in at 3.4x. A rifle scope, not a
telescope. The MAIN view still narrows with them — by a tenth and then a
sixth — which is much less than the panel magnifies, and the difference
is the point: the actual magnification is on the gun's screen where the
user asked for it, and the picture only narrows enough that holding a
scope feels like bracing. The look sensitivity drops by exactly the
factor the view narrowed by, because a narrowed field of view with
unchanged sensitivity is a mouse that has become twice as twitchy at the
moment you were trying to be careful.


AND ITS VOICE
-------------

Six recordings, the user's own, and between them they are the whole
voice of the weapon — the first one in this game that is recorded rather
than synthesised end to end:

  lance_charge_start   the moment the trigger goes down
  lance_charge_loop    two seconds of coil, held round and round
  lance_charge_full    the stage-three whine, which takes over the
                       moment the third mark is passed and is the sound
                       of a gun that has stopped asking
  lance_prefire        the transient the instant the trigger comes UP
  lance_fire_a / _b    and the discharge, in two layers, played together
                       because it was mixed as two

A .WAV DOES NOT LOOP, and the user heard it. `src.loop = true` sends the
playhead from the last sample straight back to the first, and unless the
file was cut on a zero crossing with matching phase on both sides —
which no recording of a real coil ever is — that jump is a step in the
waveform, which is a click, once every two seconds, for the whole seven
seconds the trigger is down.

The ordinary fix is to play two copies half a period apart and crossfade
between them for ever. It works, and it is the wrong fix HERE, for one
reason: this loop is PITCH-RAMPED. A playback rate that climbs from 0.72
to 1.45 is a loop period that shrinks by a third over seven seconds, and
a crossfade scheduled against a period that is moving has to be
rescheduled continuously — any drift puts the fade somewhere other than
over the seam, which is a click again, at a moment you cannot predict.

So the join is baked into the SAMPLES instead, once, when the file
decodes. A buffer of length L becomes one of length L - X: the middle is
copied through, and the first X samples are the head mixed with the TAIL
that was cut off, equal power, the tail fading out as the head fades in.
Position 0 of the loop IS sample n of the original, which is the sample
that followed n-1, which is the last sample of the loop. The join is
exact, and it is exact at ANY playback rate, so the pitch can do
whatever it likes. Equal power rather than a straight line because the
two sides are different parts of the same continuous noise and so are
uncorrelated: summed linearly their energy dips in the middle of the
fade, which is audible as a breath.

ALL OF IT RISES TOGETHER, at the user's request. One number —
Player.chargePitch, the charge as a fraction, mapped to 0.72..1.45 — is
read by every charge sound, so the start, the loop and the stage-three
whine are one accelerating sound rather than three sounds that happen in
a row. There is no formant correction and none is wanted: what a coil
winding up actually does is get faster and higher together. The
discharge picks up where the charge left off — the transient goes off at
the pitch the coil had reached — and the two layers of the shot go the
other way, a bigger stage being LOWER and longer, because that is what
more of something sounds like.

AND A CHARGE THAT IS NEVER FIRED FIZZLES. The same coil, played once
rather than round and round, from wherever the pitch had got to and
sliding down below where it started while it fades. A separate recording
would be a second voice arriving at the moment the first one stopped.
It is the same call for both ways of ending a charge without a shot — a
trigger that came up under the first mark, and one that stayed down past
the hold — because they are the same event.

The stage-three whine is RELEASED and not stopped, which is the
difference between a sound ending and a sound being cut: it is eleven
seconds long and is only ever heard for the three the hold allows, so
whatever happens next wants its tail under it rather than silence. The
two-second loop is stopped, because a loop has no tail to keep. And the
whole thing is judged from the state AFTER the tic rather than switched
at the moment something happens, so every way of ending a charge — the
trigger coming up, the shot going off, the weapon being swapped, dying
with it in your hands — stops the loop through one line, and none of
them has to remember to.


MEWD Editor, THE MAP EDITOR

At the user's request: a map editor for this game in the mould of SLADE
and Ultimate Doom Builder. Type E or EDIT at the terminal, or open index.html?edit to go straight in. It is the
Doom mapping workflow: sectors drawn on a grid, vertices dragged, the
plan and the 3D view together, a floor raised with the mouse wheel,
and one key to test the map. But the engine under it is actually 3D, so
every mode works in the 3D view as well as on the plan. It also places
free boxes anywhere in space, and it spreads sprite people and
decorations procedurally.

ONE WORKSPACE, BOTH VIEWS. The editor opens in the COMBINED layout: the
3D view fills the window and the plan is inset in its bottom-left
corner. Both are live, and Tab (or the button on the inset) swaps which
one is big. Split, 2D-only and 3D-only are on the bar too. The two views
share what is half-done: the outline being drawn, the drag and the
cursor. So a room can be started on the plan and finished in 3D, and
the 3D camera is drawn on the plan.

SLOPES AND STOREYS ARE SWITCHED OFF FOR NOW, at the user's request.
FEATURES in js/editor/doc.js is the switch. The inspector does not offer
them, and the compiler ignores them, so a map that has some is built
flat and single-storey, exactly as it can be edited. The code is still
there and still tested, with the switch thrown.

  js/editor/doc.js     the map as a JSON document, the undo stack, and
                       the compiler that turns the document into a Level
  js/editor/editor.js  the state everything shares, the edits, the
                       keyboard, and the boot
  js/editor/view2d.js  the plan, which is the Doom Builder half
  js/editor/view3d.js  the 3D view, drawn by the game's own renderer,
                       with every mode working in it
  js/editor/scatter.js the procedural spreads
  js/editor/ui.js      the bars, the inspector and the texture browser
  css/editor.css       its look, loaded only with it

WHAT YOU SEE IS WHAT YOU PLAY. The 3D view is js/mapgeo.js building the
level the compiler made, with the game's own textures, its world shader
and its baked sky. There is no second renderer to drift from the first.
PLAY (F5) stores the document and reloads with ?play. js/main.js
compiles it with the same compiler and runs it instead of THE GRID, and
F2 in the game comes back to the editor with ?edit. The map is autosaved
in the browser as you work. File > Save writes a .gssmap.json, and
File > Open reads one back.

THE MODES, one key each, as in Doom Builder:

  V  vertices      click, drag, Shift adds, Del removes
  L  lines         Del joins the two sectors on a line into one
  S  sectors       click, drag, box-select on empty ground
  T  things        click empty floor to place; , and . turn them
  P  props         drag on empty ground to draw a box in space
  D  draw          click the corners, click the first to close (Enter
                   closes, Backspace takes a corner back, Space enters)
  R  rectangle     drag a sector out
  X  scatter       drag a circle out from its middle to spread the mix
                   chosen in the Scatter tab (Alt paints over another)

A corner that lands on an existing vertex uses it. One that lands on a
line splits it, in every sector the line belongs to. A sector drawn
inside another takes that one's heights and textures. Drawn clear of its
walls, it is a hole, and the compiler cuts it in with a slit, because a
sector in this engine is one ring. Drawn against the wall, it is cut out
of the parent, and one drawn wall to wall splits the parent in two. A
vertex dropped on another is welded to it when the button comes up. [
and ] step the grid through Doom Builder's own powers of two. G toggles
snap, F frames the map, Tab flips between the 2D and 3D views, and
Ctrl+Z / Ctrl+Y undo and redo everything, drags included.

THE 3D VIEW. Every mode works here as it does on the plan. Vertices have
handles you drag across the floor. Clicking a wall picks its line, and
clicking a floor or ceiling picks its sector; either can then be
dragged. Things are placed by clicking the floor. Props, rectangles and
scatter circles are dragged out across the floor. Draw mode clicks
corners on the floor. A drag moves across a level plane at the height
it was grabbed at, on the same grid as the plan, and it is the same
drag, so it undoes the same way. Hold the right button to look; while
it is held, WASD, Q and E fly (Shift faster). While it is not held,
those letters are the mode keys. The wheel over a floor or ceiling
raises it (8 a notch, 1 with Shift), with every selected sector if it
is one of them. Over a wall it moves the step, and over a prop it lifts
the prop. With a surface picked, clicking a texture in the browser
paints it. Ctrl+C over a surface copies its texture and Ctrl+V pastes
it. B turns fullbright on and off, and F goes back to the start. Plants
and people are drawn as the game draws them: billboards standing on the
floor and turning to face you. Plants use their own pictures from
assets/forest/, and people are figures in their type's colour. The wall textures of THE GRID are black between their
lines, so every edge in the map is also drawn faintly, where a wall is
whether its texture shows it or not. Picking is worked out against the
document, not the triangles: a ray against every sector's floor and
ceiling planes, every line and every prop. The answer is therefore a
sector of the map and a part of it, which is what an edit needs.

THE INSPECTOR edits everything selected at once:

  sectors  name; floor, wall height (or ceiling, with a roof on) and
           light; SKY, NO CEILING (on by default); the five Doom 64
           colours; floor, ceiling, wall, upper and lower textures; and
           a button to scatter the chosen mix into them
  lines    blocks walking, blocks sight, and the SIDEDEF: top, middle
           and bottom textures, x and y offsets, and upper and lower
           unpegged
  things   type, place, facing (with an eight-way compass), variant; a
           plant's kind and scale
  props    the box's extent, bottom, top, and side and top textures
  scatters everything below

IT BEHAVES LIKE ULTIMATE DOOM BUILDER AND SLADE3 where they agree, at
the user's request:

  Q               visual mode: the 3D view alone, the mouse looking, a
                  crosshair to pick with (surfaces and things, whatever
                  the plan's mode), WASD to fly, Space and C for up and
                  down; Q or Esc to leave
  wheel (3D)      raise or lower the floor or ceiling under the mouse,
                  8 a notch (Shift: 1), every selected sector with it
  Ctrl+wheel      SECTOR BRIGHTNESS, on the plan or in 3D: Doom's 0-255
                  in its sixteen steps (Shift: 1). Over a thing, the
                  sector it stands in. The inspector has it as a slider.
  PgUp / PgDn     floor of the selected or highlighted sectors up or
                  down 8 (Shift: the ceiling), on the plan or in 3D
  right-click     the thing under the mouse, in the inspector (its
                  properties); right-drag moves it; on nothing, pans
  Insert          a thing at the cursor, or a vertex (in vertex mode,
                  splitting the line it lands on); in things mode a
                  double-click on the floor places one too, and a click
                  or a drag on empty floor selects, as in every mode
  Delete          the selection, or the highlighted element of the
                  current mode if nothing is selected
  finishing       in draw mode, Enter, the right button or a double-
                  click finishes: a line drawn from wall to wall SPLITS
                  the room it crosses; clicking the first corner closes
                  a new sector; either way drawing hands back to the
                  mode it started from
  undo            a run of wheel notches is one step; Ctrl+Z is the
                  map's undo even with an inspector field focused
  B               fullbright, from either view
  Ctrl+C / Ctrl+V copy the selection and paste it at the cursor
                  (sectors, things, props, scatters); in 3D over a
                  surface, its texture
  arrows (3D)     a wall's texture offsets, 1 at a time (Shift: 8)
  V L S T         vertices, lines, sectors, things, as in Doom Builder
  [ ] G           the grid, and snapping to it

AND WHAT CAME AFTER THE REVIEW, the four things it listed as not yet
Doom Builder:

  TWO SIDES TO A LINE. Every line has a side facing each sector it
  bounds, with its own top, middle and bottom textures and offsets,
  as Doom's front and back sidedefs do. They are kept by the sector the
  face looks into (lines[key].sides, read face by face by sideOf in
  js/mapgeo.js). Painting a wall in 3D paints the face you are looking
  at; the arrow keys move that face's offsets; the line inspector shows
  both sides by name, with Swap sides (Doom Builder's Flip Sidedefs).
  A building's wall can be brick outside and panelling in.

  DRAWING FROM A BLANK MAP, at the user's request, who could only move
  the one sector a new map has. That sector is THE GROUND (the only
  sector, or the outermost with rooms in it; Editor.isGround), and in
  Sectors mode:
    drag on the ground    draws a new rectangular sector, on the plan
                          or on the 3D floor (Editor.addRect)
    click on the ground   selects it, as before
    Alt-drag the ground   moves it, which is the old behaviour
    drag a room           moves the room, as before
    Insert (or Space, D)  starts a drawing of any shape at the cursor:
                          click the corners, click the first one or
                          press Enter to finish, Esc to cancel
  A rectangle that snaps to nothing on the grid says so, and File > New
  map, Open and Open demo frame the plan and put the 3D camera at the
  start. In 3D, near the camera a lot of screen is only a few units: a
  rectangle drawn there is small, and one drawn further off is not.
  DRAWING ACROSS WALLS. A sector drawn across existing lines is cut
  where it crosses them (and so are they), and every room it passes
  through is split along the part of it inside that room: each piece is
  its own sector, keeping the room's heights and textures, and the
  pieces are selected. What lies outside every sector is not made.

  LINEDEFS, SHAPES AND FINGERS, at the user's request, who still could
  not draw what they wanted on the plan:
    Draw (D), finished open — Enter, a double-click or the right
      button — is LINEDEFS OF THEIR OWN (doc.linedefs, yellow on the
      plan) unless it runs wall to wall across a room, which splits the
      room as before. Each leg is cut wherever it crosses a line.
      Wherever the new ones close a shape, among themselves or against
      the walls already there, that shape becomes a sector at once
      (closeLoops walks the map's lines as a plane graph, face by face).
      What stays open stands as a wall when the map is built
      (linedefWalls in js/editor/doc.js): a thin sector 8 thick, 128
      high outdoors and floor to ceiling in a room, in the line's middle
      texture — the line inspector sets its texture and height. Lines
      mode selects them; Delete removes one without touching a sector.
      One that would cross a wall or leave the map is listed as a
      problem instead of built.
    Shape (R) drags out the shape chosen beside its button: rectangle,
      ellipse, circle, polygon, triangle, diamond, star, L-shape or
      half-round, fitted to the box dragged (shapePoints). The number
      beside it is a round shape's sides or a star's points. A drag on
      the ground in Sectors mode draws the same shape.
    A finger draws: the views take touches as pointer input
      (touch-action: none), so a tablet taps corners and drags shapes
      instead of scrolling the page.

  AN S PEN, or any pen, on the plan (View2D in js/editor/view2d.js):
    the pen draws, and hovering it shows where a corner will go;
    once a pen has touched the glass, a FINGER only moves the view —
      one pans, two pinch to zoom — so a resting palm draws nothing
      (before a pen, one finger draws and two pinch, and a corner the
      first finger put down just before the second is taken back);
    a DOUBLE-TAP finishes a drawing, as a double-click does;
    the SIDE BUTTON is the right mouse button: it finishes a drawing,
      moves what it drags, pans on empty ground and opens what it taps
      in the inspector;
    the ERASER end, on a pen that has one, deletes what it touches;
    a tap is allowed 6 pixels of wobble with a pen, 10 with a finger.
  THE PAD (buildPad): the keys a tablet has not got, as buttons at the
  bottom right of the plan, shown on a touch screen or once a pen or a
  finger is used — while drawing: Close, Lines (Enter), take back a
  corner (Backspace), give up (Esc); otherwise Undo, Redo, Delete, zoom
  out, zoom in and Frame. On a touch screen the bar's buttons are
  bigger; on a narrow one the bar wraps, the side panel goes under the
  views and the key help is hidden.

  LINING TEXTURES UP ON MANY LINES AT ONCE (alignTextures in
  js/editor/doc.js), Doom Builder's auto-align and fit. Select the lines
  (L, then click, Shift-click or box them) and use Alignment in the
  inspector — or Shift+A, in either view, for Align X:
    Align X     each run of joined lines carries its texture on from
                one line to the next, both sides separately, so there
                is no seam at a corner (a closed room keeps one, where
                its run meets its own start, unless Fit across made the
                way round a whole number of repeats)
    Align Y     every side takes the first line's y offset
    Match       every side takes the first line's scale and y offset,
                then Align X
    Fit across  each run is stretched a touch so its texture repeats a
                whole number of times along it, then Align X
    Fit up      each wall is stretched a touch so its texture fits a
                whole number of times from its floor to its top
    Scale all   one x or y scale for every side of every selected line
    Reset       no offsets, no scale
  A side has its own scale now as well as its offsets (sides[id].xscale
  and yscale; 2 is twice as big, half as often), set on the Inspect
  tab and drawn by js/mapgeo.js. A linedef standing on its own is a
  wall sector when the map is built, and is left out.

  THE GRID AND THE AXES, Blender's way, so you always know where you
  are. In 3D the plan's grid lies on the ground at height 0, laid out
  from the origin — a line every grid step, a bright one every eight —
  and fades into the distance round the camera; the X axis is red, the
  Y axis green and Z (up) blue, through 0,0,0, which has a white dot
  on it you can see through walls. The gizmo in the top right corner
  shows which way X, Y and Z point from where you are looking. In the
  modes that put something down (draw, shape, vertices, things, props,
  scatter) the grid comes up to the floor under the mouse and fades
  round the cursor instead, so a corner clicked in 3D lands where you
  can see it will. H hides the grid, the axes and the gizmo, and brings
  them back.
  On the plan the X axis is red along y = 0 and the Y axis green along
  x = 0, the origin is ringed and labelled 0,0,0, and when it is off the
  screen an arrow on the edge points back to it with how far it is. The
  key in the bottom left corner shows X and Y (and Z, the dot, coming
  up out of the screen).

  THE USER'S OWN GROUND AND PLANTS, from github.com/verdictzero/vandre
  (rebuilt by tools/prep-vandre.py /path/to/vandre):
    21 ground textures in the pack, 256 square, one tile 128 units —
      vandre/terrain: ARCTIC1 FROZEN1 TUNDRA1 FARMLND1 SAND1 SAVANNA1
      WASTE1 PINEBAR1 MEADOW1-5 GRASCHK1 GRASCHK2 MOLTEN1 CANDY1;
      vandre/city: CITYCON1 CITYMET1 CITYMET2 CITYSKRT. Type the name
      in the Textures tab's filter.
    69 plants (js/forest.js KINDS with a `set`), each with its burn
      map, in eight sets: desert, meadow, new meadow, pine barrens,
      savanna, wasteland, farmland, tundra. The Things tab shelves the
      plants by set; the wood never plants them by itself, and the game
      fetches one only when the map it is playing uses it.
    A scatter preset for each biome (Scatter tab): desert, meadow,
      meadowOld, pine, savanna, wasteland, tundra, farmland, each named
      with the ground that goes with it.
    The Sprawl shows every one of them in 21 biome beds down the west
      edge of its meadow block, since it wears the whole pack.

  A NEW MAP IS BRIGHT: its ground is full bright (255), with a little
  white ambient light everywhere (World: 35), and walled round 256 high
  rather than 1024 (GROUND_DEFAULTS and NEW_MAP_AMBIENT in
  js/editor/doc.js). What is drawn on it takes the same.

  SNAP STAYS WHERE YOU LEFT IT. Snap on or off (G, or the button, which
  now says "Snap on" / "Snap off") and the grid size are remembered
  between visits (localStorage gss-edit:prefs). With snap on everything
  that places or moves snaps — corners, shapes, things, props, scatter
  brushes, drags and arrow nudges to the grid, and heights too: the
  wheel and PgUp/PgDn land a floor, a ceiling or a prop on a multiple
  of the step (8, or 1 with Shift), so a floor at 3 goes to 8, not 11.

  LAYERS: THE MAP IN STOREYS, up the Z axis. Layer 0 is the ground and
  what stands on it. Go up a layer (the ▲ by "Layer 0" in the toolbar,
  or Alt+PgUp; ▼ / Alt+PgDn for down) and the plan is empty, with the
  layers under it ghosted in blue-grey and the ones over it dashed in
  orange: draw there exactly as on the ground. A room drawn on layer 1
  stands on the room of the layer under it — its floor on that one's
  ceiling, as tall, in its textures — and its corners snap to the
  corners under it, so a storey goes straight up. So:
      layer 0   the ground, and the ground floor of a house (roof it,
                Inside, or give it walls)
      layer 1   the first floor, standing on it: its floor IS the
                ceiling of the room under it
      layer 2   the next, and so on; layer -1 is a cellar under the
                ground.
  Each layer is a plan of its own (vertices, sectors, lines and linedefs,
  nothing shared), so every tool works on it as it does on the ground.
  The quick way up: select the ground floor's rooms, Ctrl+C, go up a
  layer, Ctrl+Shift+V (paste in place) — the copy stands on top.
  Things put down on a layer are on it (and stand on its floor in the
  game); things of other layers are ghosts you cannot pick. A problem
  on another layer takes you there when you click it.
  How it is built (js/editor/doc.js, LAYERS and compileLayers): every
  layer's outlines are laid over each other and cut where they cross
  (overlay), and each piece of the map becomes a column of the rooms of
  every layer over it — the engine's own room-over-room (MapBuilder.
  column). A room's ceiling meets the floor of the one over it; one
  open to the sky under another gets that one's floor over it instead;
  only the top room of a column has a roof. The outside wall of a house
  goes up only in the openings that are inside against outside, so a
  roof terrace is open air, and you can walk off it. In the game,
  standing on a deck is standing in the storey above it (Level.spanIn).
  A map on one layer is the same file it always was.

  THE STEP GENERATOR (js/editor/steps.js), in the Inspect tab of a
  sector, under Heights:
    ▤ Stairs  draw a sector between two of different heights — the
              street and a terrace, a floor and the next layer's — and
              Make stairs cuts it across into steps from the low
              neighbour up to the high one: as many as keep each rise
              to the step height (16), the last a step below the top.
              Give "Climb to" a height to climb to something else.
    ◎ Rings   cuts the sector into rings, one inside the next, from its
              own floor to "Middle at" in the middle: above it for a
              mound, a mesa or a cliff in terraces, below it for a
              caldera, a pit or an amphitheatre.
  Both keep each step's head-room (tick it off to leave the ceilings),
  are one undo, and leave ordinary sectors behind — the rooms either
  side get the new corners, so everything still meets.

  TWO PANELS. The inspector has the right-hand side to itself and is
  always showing what is selected; the tabs — Textures, Things, Scatter,
  Map — are down the left, so a texture or a thing can be picked with
  the selection's properties still in view. Tabs in the toolbar puts
  the left panel away for more room to draw (remembered); clicking a
  texture field in the inspector brings it back. On a narrow screen the
  two sit side by side under the views.

  BACK TO THE EDITOR FROM A TEST RUN. Play (F5) opens the game on the
  map with a "◀ EDITOR F2" chip at the top of the screen (tap it) and
  BACK TO EDITOR in the pause menu (Esc); F2 goes back from anywhere.
  The editor opens on the map as it was played.

  THE PLAN'S VIEWS. The selector on the plan (or K) shades every sector
  by its brightness, its floor or its ceiling, with the number on it —
  Doom Builder's brightness view, and its height views.

  A ROOM TOUCHING AT A CORNER. A room whose corner sits on the wall of
  the sector round it is a hole in that sector pinched to the wall at
  the corner, and can be walked into like any other room.

AN ADVERSARIAL REVIEW, by two separate reviewers — one driving the editor
with a real mouse and keyboard as a Doom Builder mapper would, one
attacking the compiler, the undo stack, test runs and the Godot export
with real Godot — found, among others: menus the bar clipped, a Scatter
tab that stopped the 3D view rebuilding, visual-mode clicks that did
nothing, Delete taking a whole sector, dialogs that let keys through,
rooms side by side with no wall between them, merges that lost rooms
drawn the other way round, doorways lost on a split, colours shared
between sectors. All of them are fixed and each one is held down by a
check in the smoke test.

THE INFO BAR along the bottom says what is under the mouse, in either
view: a sector's floor, ceiling, brightness, whether it is inside, and
its textures; a line's length and sides; a thing's type, place and
facing.

INSIDE AND OUTSIDE. Every sector is one or the other; it is the first
setting in the sector inspector. OUTSIDE is open ground under the sky,
with no ceiling, and its height is only how tall walls round it stand.
INSIDE is a room with a roof, 128 high to start with. Where an inside
sector meets an outside one the compiler stands the building's outside
wall (5c in js/editor/doc.js): solid, the inside sector's wall texture,
from its floor to its roof, blocking walking and sight. The roof is
drawn from above, and no wall runs from it up to the sky. To make a
door, mark the line a DOORWAY in the line inspector; to make a doorway
in part of a wall, split the wall first (Insert, in vertex mode). On
the plan, inside is tan and hatched, the outside wall is drawn solid,
and a doorway dashed.

EXPORT TO GODOT (File > Export Godot scene; js/editor/godot.js). The
map goes out as a zip that unpacks into one folder for a Godot 4
project:

  <name>.tscn    the scene to open: a WorldEnvironment with the map's
                 sky, the level, the plants and the static decor
                 (trolleys, bollards, crates, fuel cans, headstones, in
                 the game's own drawings) as Sprite3D billboards
                 (fixed-Y, cut out, point sampled, feet on the floor,
                 their sector's light and colour baked into modulate),
                 the game's actors and the lamps as Marker3D nodes
                 carrying their type, variant and facing, and the
                 player start
  world.glb      every surface of the level, from the game's own
                 geometry: one primitive per texture, UV-mapped as the
                 game maps it, textures packed inside
  textures/      the same textures as PNG files
  sprites/       the billboards' pictures: each plant's, drawn at its
                 aspect, and each decor thing's, front view
  README.txt

Sector brightness and Doom 64 colours are baked into the vertex colours
and the materials are unshaded (KHR_materials_unlit), so the scene looks
like the map with no lights placed; untick BAKE LIGHTING for lit
materials and a sun. The level mesh is named World-col, so Godot's
importer gives it a static trimesh collision body. The scale is 32 map
units to the metre, which can be changed. An export was imported into
Godot 4.3 headless to check it: the scene loads, every surface has its
texture, UVs and vertex colours with unshaded materials, the collision
body is there, and the sprites and markers are where they should be.

AUTOMATIC COLLISION BOXES. At the user's request, each billboard that
stops you in the game gets its own collision in the export: a
StaticBody3D child holding a BoxShape3D, the axis-aligned bounds of
the cylinder the game collides with, standing on the floor. For a tree
or bush that is its trunk radius and its height (a fir_tall_1 is
0.875 m across and 9.4 m tall at 32 units to the metre). For the
trolley, bollard, crate and headstone it is the thing's radius and
height in js/states.js. Ferns, grass and the fuel can, which you walk
through in the game, get none. Boxes of one size share one shape, and
the COLLISION tick box turns them off with the level's. Checked in
Godot 4.3: every box loads at its size and place, and a ray through
each billboard hits its own box, except the fuel can's.

AN OPEN WORLD BY DEFAULT. A new map is open ground under the sky with
no ceiling, 4096 units square, and a new sector is too. Its "ceiling"
is SKY, which the renderer treats as a hole the sky shows through, and
its height is only how tall the walls round it stand. Turn SKY, NO
CEILING off for a sector and it gets a roof. Seen from outside, the
roof is drawn as a roof, and no wall runs from it up to the sky the way
Doom's upper texture would. That would put a tower on every room, so it
is off unless the map asks for it (Doom sky walls, in the Map tab).

DOOM 64 COLOURS. As in Doom 64, a sector's light has colours. There are
five: the floor, the ceiling, the things standing in it, and its walls,
which run from the top colour down to the bottom one. Each can be
ticked on or left white, and a row of moods sets all five at once: warm
lamp, cold light, toxic, blood, hell, night and violet. The renderer
carries a colour for every corner (tintRGB, in js/mapgeo.js). Floors
and ceilings take theirs flat, walls take theirs graded by height over
the sector, and the world shader multiplies it into the picture. Sprites
standing in the sector take its thing colour, in the game through
js/standees.js. The editor's 3D view is the same renderer, so what you
colour is what you play. A wall is coloured by the sector on the side
you see it from, as in Doom 64. Under the open sky there is no ceiling
to grade to, so each piece of wall is graded over its own height: the
step round a pit runs from the top colour at its rim to the bottom one
at its foot.

A ROOM DRAWN INSIDE ANOTHER is a hole in it. The engine's sectors are
single rings, so the compiler bridges the hole in with a slit. The
floor round a hole is triangulated from the real outline and holes
(flatOuter and flatHoles, read by addFlats in js/mapgeo.js), because a
slit ring handed to the triangulator came back with the holes filled
in, and a pit had the ground drawn over it.

THE SIDEDEF, Doom's way. A one-sided line has its middle texture. A
two-sided one has a top (upper), a bottom (lower), and a MIDDLE that
stands in the opening, such as a fence, a grating or a window, with a
height if it is shorter than the gap. Every line has x and y offsets
and Doom's two flags. Upper unpegged hangs the top texture from the
ceiling. Lower unpegged measures the bottom texture from the ceiling
and sits a one-sided middle on the floor. In 3D, the arrow keys over a
wall move its texture, 1 at a time or 8 with Shift, as they do in Doom
Builder's visual mode.

THE TEXTURE PACK (js/texpack.js, assets/textures, assets/skies). Two
sets of pictures the user handed over, 245 textures in all: concrete,
grass, dirt, cliffs, the ops-room panels and doors, water, an office,
backdrops, test and debug tiles. They are files, not drawn, and go into
the same TextureBank as the game's own, so any surface can wear one.
The Textures tab puts every texture, the game's own and the pack's, on
one of three shelves: Animated, Square and Non-square. Shape is judged
by the size on a wall, so the 64 by 112 windows are non-square. Your
map's own textures stay at the top.
A pack picture spans half its pixel size in world units, because it is
drawn at twice Doom's resolution: the doors come out 64 by 128, a Doom
door. DR1 and the test tiles (64TEST says "64px" on it) are one to one.

THE ANIMATED ONES run Doom's way (ANIMATED, p_spec.c). Each frame is
held for 8 tics of 35 a second, and every frame of a run animates from
its own place in it, so DEVPAN1E starts its cycle at E. The runs:
DEVPAN1A-L, DEVPAN2A-H, DR1_01-12, EYEDOOR0-8, EYEDORC0-4 (EYEDOORC
stays still), REACTB00-04, WFALLA1-4, WAT201-224 and TESTPA00-74. The
last two are moving pictures, 24 frames of water and 75 of a test card,
and are held for 4 and 2 tics, the way GZDoom's ANIMDEFS gives a run
its own speed; at 8 the card took seventeen seconds to go round. A run
is one cell in the browser with its frame count on it; type in the
filter to see every frame. They animate in the editor's views, in a
test run, and in a Godot export, where doom_anim.gd steps the materials
at the same rate.

NOT SQUARE, AND TALL. A texture's width and height are separate
numbers everywhere. Walls repeat along a line by the width and up it by
the height, and floors do the same on each axis. The browser draws each
thumbnail in its own shape, so a tall door is tall and a treeline is a
strip. A map texture started from another keeps its shape: one too big
is brought down evenly, and it keeps the source's size on a wall. The
middle texture of a two-sided line (a fence, a door, a treeline in a
gap) is drawn ONCE, its own height, as Doom draws one, and repeats only
along the line. A 64 by 128 DR1 in a 1024-high opening is 128 tall, not
eight doors stacked up. It stands on the floor, since an open world's
gaps reach the cloud base, and the y offset lifts it. A line given a
Middle height keeps that height, and the outside wall of a building
still fills its opening.

THE DEFAULTS. A new map (File > New, or THE GRID when there is no
autosave) starts on checkered grass (LAWN2) under the pack's day sky
with scattered cloud (BSKY2), and a sector drawn in it has the same
grass floor. A map saved before this keeps what it had, including a
painted sky: the skybox belongs to each new map, not to the world's
defaults, so "painted" on the Map tab still means painted.

LIGHT AND FOG. Per sector, on the Inspect tab:
  Light colour   one colour for all the light in the sector, multiplied
                 into its Doom 64 colours (white where they are unset)
  Fog            a colour and a density, 1 to 100, GZDoom's way: the
                 fog is half-way in at 25600/density units (100 is thick
                 at 256, 10 at 2560)
For the whole map, on the Map tab:
  Light colour        the colour of every light in the map
  Ambient light       light that is everywhere, a colour and a strength,
                      added to every surface however dark its sector
  Ambient in fog      how much of the ambient is in every fog: a warm
                      ambient turns a blue fog lilac
  Fog colour, density the fog of every sector without its own, and of
                      everything that has no sector (sprites, trees)
  Override fog colour the map's fog colour on every sector's fog (each
                      keeps its own density) and on the far haze, in
                      place of the sky's horizon
The fog goes on after the far haze. It is lit by the map's light colour
and carries the ambient, and fullbright (B) turns it off to look at
textures. It all lives in the shared world shading (js/material.js:
applyMapLight, the SECTOR FOG block of worldShade), so walls, floors,
sprites, trees and particles all take the map's light. Sector fog
reaches walls, floors and ceilings through a per-vertex attribute
beside the Doom 64 tint. Everything is off at its defaults, so the
game's own levels are untouched.

WHAT STANDS IN A SECTOR takes its light, its colour and its fog too, as
a thing does in Doom: sprites, trees, the editor's plants and people,
and 3D boxes. The sectors are handed to all of them at once as the
SECTOR GRID (js/sectorgrid.js): two small pictures over the map's floor
plan, a cell every 16 to 40 units, each holding the light, thing colour
and fog of the sector at its middle. A vertex shader reads the cell
under its object's foot (SECTOR_GRID_GLSL in js/material.js), so
anything drawn through the world shading picks it up without its own
code being told. A standee, which the game already lights and colours
by its sector, takes the fog from it; a model takes all three, its own
shading times the sector's light; trees and the editor's billboards
take all three. A 3D box takes the sector under its middle when the map
is compiled, unless it has a light of its own. The grid is only laid
down for a map from the editor; the game's own levels light their
things themselves.

AND WHAT MOVES EASES ACROSS. A person or monster walking from one sector
into another does not snap to the new light, colour and fog: it eases
there with a time constant of 0.06 seconds, so it is most of the way in
a tenth of a second and all of it in a quarter (tweenLook in
js/sectorgrid.js). The eased fog goes to the sprite batch per instance
(iFog in js/standees.js). A fog coming in from none takes its colour at
once and only thickens, so nobody is greyed on the way into a blue fog.

FOG FADES FROM SECTOR TO SECTOR, AND INTO THE SKY. At the user's request
the fog is no longer read off the surface. It used to fog each surface
by its own sector's fog over the whole distance to it, which gave a
fogged room's floor a hard edge at the sector line and left the sky
clear however thick the fog you stood in. Now, on a map from the editor
with any fog, the fog is followed along each line of sight over the
sector grid (FOG_GLSL in js/material.js). The line is cut into 16
pieces, finer near the eye, and each crossing into another sector's
air is found by halving the piece it falls in, 5 times. Each stretch
fogs by its own air, so fog builds up with how much of it you look
through:
  - walking into a fogged room, it closes round you step by step, with
    no jump at the doorway
  - a floor just over the sector line is barely fogged, with no edge
  - looking out of a fog, what is beyond is hazed by the fog still
    around you
  - the sky is followed the same way out to the far edge of the air,
    so it fades into the fog you are in and clears as you walk out
A fog also has a TOP: the ceiling indoors, or 320 units over the floor
under the sky (FOG_TOP in js/sectorgrid.js; a third grid picture holds
it). Above its top it thins away every 128 units (FOG_FADE). So a
fogged field seen from outside is a fog bank fading up into the sky,
not a column to the stars, and standing in it the sky overhead is
dimmed only by the fog above you. Under a roof the fog stops dead at
the ceiling, so the air over a fogged building is clear. Along one
stretch of the same air the top is the one it had where the stretch
began, so a line of sight over a street of kerbs and roofs is not
banded by each one's slightly different height. The game's own levels,
which have no fog, are untouched.

THE SPRAWL, THE GAME'S OWN WORLD (js/maps/sprawl.js). At the user's
request: a sprawling level made of every asset the user has given and
none that were generated. MEWD at the terminal opens it, and so does a
reload; DEMO and index.html?demo say so outright; index.html?grid is
THE GRID, the test area the game used to open in. Or open it in the
editor (File > Open demo: THE SPRAWL) to take it apart. It is an
editor document built in code, the same every time.

  THE LAYOUT  sixteen blocks, 3200 units square, on a four by four grid
              with roads 768 wide, about half a kilometre across, on a
              floor sunk 686 units into a grass plateau. The cliff all
              round is ONE face of the pack's big rock cliff (CLIFF2),
              one line a side so it has no seam, with a verge of earth,
              grass and ferns at its foot. The plateau has no outer wall
              (wallTex NONE): what is past it is the sky. On it, seen
              over the cliff edge from the streets and butted end to end
              so no slit of sky shows between them, stand the pack's
              painted horizons — a tree line, a meadow, ruins — with
              mountains behind the short ones (behind the 512-tall ones
              they would never be seen), and firs along the edge. The
              roads are lit up (ASPHALT1 is a dark picture), dashed down
              the middle, with a hatched box junction at the crossroads
              where you start. Every block has a pavement with the
              user's photographed street lamps and street trees — none
              at a side's middle, where the crossing and the district's
              way in are — and a crossing at each corner.
  THE SCALE   where every texture goes is decided by what it is, at its
              own size: the pack is 2 pixels to the unit, so a 256-pixel
              panel is 128 units, and the walls, doors, screens and
              consoles are cut to those sizes so a panel is a panel and
              not a quarter of one. A door (DR1, EYEDOOR) is 64 by 128,
              standing in a jamb of its own height notched into the
              building; a monitor and a keyboard are 256 by 128 — wall
              screens and console decks; the cubicle panel (OFCCUB01) is
              256 tall and the cube farm's walls are that tall; the
              mansion's panelling (MANINT1) is 512 tall in two rows and
              its walls are one row. The coloured checkers (XTX_5..8)
              and the TEST and DEBUG sets are test cards, and they live
              in the test chamber only. Every building wears a facade
              outside and its own walls inside, by the line's two sides
              (sides in js/editor/doc.js), and a roof of its own.
  THE BLOCKS  south to north, west to east:
                the park (a mown lawn, slab paths, a pond, ivy hedges) ·
                the car park (bays, a hatched strip, a kiosk with
                roller shutters) · the cube farm (panel walls, cubicles,
                a meeting screen, green-glass windows, eye doors) · the
                plaza (inlays, a stage with the test card on a screen
                between ribbed pillars and a monitor each side, the
                GZDOOM badge)
                the cemetery (the iron, stones in ranks, an earth path,
                mist, a ribbed mausoleum with a shut eye door) · the ops
                centre (riveted outside; a band of the pack's panels at
                their own size inside, console decks of keyboard and
                monitor, a red reactor room with the glowing beam round
                its top, three doors) · the mansion (one row of
                panelling, windows, a courtyard with a fountain reached
                by arches) · the market square (wood counters, metal
                posts, cloth awnings, a pavilion)
                the wood (dense firs, undergrowth, a track, a mossy
                outcrop in a clearing, green mist) · the quarry (a pit of
                eight climbable benches faced in plain rock to a pool;
                a crag in two tiers — the rock cliff in front, the
                lawn-topped cliff on its sides, the tall crag behind —
                with the waterfall coming down the upper face into a
                pool and over the lip into a notch) · the brutalist hall
                (ribbed facade with two bands of windows, pillars, a
                light well open to the sky with a pit in it) · the yard
                (pads, a channel, containers in three metals with roller
                shutters, a shed)
                the meadow (grass patches, mossy outcrops, copses, a
                ring of standing stones) · the test chamber (the TEST and
                DEBUG sets, the four checkers on plinths, the squirrel,
                the test card, the badge, the two cloud strips round the
                top like a painted sky) · the lake (a beach, shallows,
                deep water, green islands, a decking jetty, a wooded
                shore) · the ruins (fallen walls whose height wanders,
                ivy, rubble at their feet)
  NO TRAPS    every drop into water or a pit is 24 or less, so anything
              you step down into you can step out of.
  ITS ASSETS  every texture in the pack, every animated run (the smoke
              test checks this); the BSKY2 skybox; the wood's firs,
              bushes, ferns and grass and the six street trees; the
              headstones, the cemetery iron and the street lamp, which
              are the user's photographs; the shoppers and townsfolk.
  NOT IN IT   anything js/textures.js paints (GRIDWALL, the drawn
              hedge), and the drawn trolley, bollard, crate, fuel can
              and ceiling lamp. The smoke test walks every surface of
              the compiled level and holds each name it wears to the
              pack, the iron, the sky and NONE.

EARTH TONES AND THE PIXEL DITHER ARE BACK, at the user's request. The
finished frame is Bayer-dithered and snapped to the earth box again,
pack textures and skies included, on a grid of 320 rows of 2:3 pixels
off a 960-row render. The sky bake is held to the box as well. Saved
settings from the full-colour spell are dropped once (PREF_VERSION 11).
The pause menu's ladders still reach full colour (PIXELS OFF, render
NATIVE). The editor's 3D view stays in full colour.

THE SKYBOXES. Seven, picked on the Map tab (Skybox): BSKY1, BSKY2,
LSKYA, NSKY1, OSKY1, UNSKY, XSKY. The sky here is a sphere wearing a
panorama, so each six-face box was joined into one by
tools/build-texpack.py. It finds the order of the four sides by
matching the edges that touch, and turns the top and bottom to meet
them, since no two tools agree on which face is "left". NSKY1 came
without its right face, and the build makes one from the two beside it.
A skybox is worn on the sphere and in the air the far walls fade to;
the painted colours are kept for when it is set back. In the Godot
export it is a PanoramaSkyMaterial.

The build is tools/build-texpack.py SRC..., run on the unpacked
archives. It drops empty alpha, halves anything over 2048 (keeping its
world size), puts the 75-frame card in 256 colours at half size, and
writes js/texpack-data.js. The game loads only the pack pictures an
edited map wears. The editor loads those first, then the rest in the
background.

THE GRID AND THE SNAP, for detailed sector work. The grid is any whole
number of units from 1 to 4096. The box on the top bar has the powers
of two, and Custom… takes any other size (24, 48, 96). [ and ] step to
the next power of two from wherever it is, so 24 goes down to 16 and
up to 32. G turns snap off and on. Shift+G snaps every corner of the
selection to the grid, welding what lands on another vertex.

A point goes where Doom Builder puts it: onto a VERTEX near the mouse;
else onto a LINE, where the line crosses the grid nearest the mouse (or
the nearest point of the line with snap off); else onto the GRID. That
holds for drawing, rectangles and Insert in vertex mode, on the plan and
in 3D. A corner put on a line splits it. A point on a diagonal sits
exactly on it, not rounded off it, and the readout shows it to two
places. The cursor shows what it snapped to: a square on a vertex, a
diamond on a line. The line being drawn shows its length and its angle.

Dragging does the same: a dragged corner snaps onto another vertex (and
welds when let go), and a single vertex onto a line, where it becomes a
corner of the sector beyond the wall too, so the two meet rather than
overlap. The arrows nudge by a grid step, or one unit with snap off
(Shift: four). Two corners one unit apart stay two corners, and a
one-unit square is a sector: vertices weld only when they are the same
point (under half a unit). Zoomed out past the grid, the plan draws
coarser lines and says so at the bottom.

THE TEXTURE EDITOR (js/editor/texeditor.js, drawn by texcompose.js).
Textures tab > + New, or double-click any game texture to start from
it. A texture of the map is a stack of LAYERS. Each layer is one of the
game's textures or an image imported from a file (brought down to 512
pixels at most). A layer can be offset, scaled, turned in quarter
turns, flipped, tiled or drawn once, tinted, blended (normal, multiply,
screen, add or overlay) and faded. The preview tiles three by three so
the seams show. Saving is one undoable edit, and everything wearing the
texture changes with it; renaming it renames every use. The textures
live in the map (doc.textures) and are drawn again whenever the map is
opened, in the editor and in a test run, so a map carries its own
textures with it. A texture with holes in it is cut out like the
game's gratings.

THE THINGS EDITOR (the Things tab):

  - Place: every thing type, and every plant with its own picture.
  - The selection: face it one of eight ways, change its type, random
    facing, random variant, snap to grid, select all of the same type,
    or delete.
  - In this map: every placed thing, filtered by type with chips or
    found by search. Click one to select it and frame it; Shift-click
    to add to the selection.

The Map tab holds the map's name, whether anything burns, whether anyone
is sent, whether upper walls go up to the sky (Doom's way), the four colours of its sky (re-baked in the 3D view as you
change them) and the PROBLEMS list: overlapping sectors, crossed rings,
a ceiling under its floor, storeys that do not stack, and no start. None
of them stops the map compiling. A map with no start gets one, and one
with nothing buildable gets a room, so a test run always has somewhere
to stand.

SPREADING THINGS PROCEDURALLY. At the user's request, sprite people
and sprite decorations can be spread over a map, not only placed one at
a time. A SCATTER is a rule, not a pile of things. It holds:

  - an area: a circle painted with the brush, a rectangle, or a set of
    sectors to fill
  - a mix: what to put down, by weight
  - a density, in things per 1024 x 1024 of floor
  - a spacing, a clumping from even to drifts, a scale range, and a seed

The compiler runs every rule on every compile, so changing any dial
re-grows the whole spread at once on the plan, in 3D and in the game.
Reseed rolls it again. Bake turns what it grew into ordinary things you
can move by hand, and drops the rule.

HOW IT GROWS (js/editor/scatter.js):

  - Darts are thrown from the seed. A dart is thrown away if it lands
    outside the area, in a sector nobody could stand in, under a prop,
    or nearer than the spacing to anything already down.
  - A smooth noise field from the same seed decides how likely a dart
    is to be kept, which is what the clumping dial turns up.
  - It stops at the count, or at 4000.
  - A scatter that cannot find room for what it asked for says so in
    the problems list.

WHAT CAN BE SPREAD is anything the game draws standing on the floor:

  - the people: SHOPPER and TOWNIE, each a random variant facing a
    random way
  - the furniture: crates, trolleys, bollards, fuel cans, gravestones
    and street lamps
  - every plant js/forest.js draws: firs, bushes, ferns, grass and the
    town's street trees

The Scatter tab has mixes ready to start from: Crowd, Townsfolk,
Forest, Scrub & grass, Street trees, Clutter and Graveyard. Single
plants can also be placed from the Things tab.

The plants reach the game as level.plants. js/forest.js grows a map
with plants and no wood as exactly those plants and nothing else
(plantsOnly there). Trees stop you, and in a world where nothing burns
they do not burn. The wood keeps one tree to a 64-unit cell, so the
compiler leaves out a second one rather than let the editor show a tree
the game will not.

The smoke test holds the compiler against the game's own Level: THE
GRID as a document, a hole, the feature switch, a line's own textures,
the open-world default and its roofs, the Doom 64 colours down to the
colour on every corner of a built surface, the sidedef's middle,
offsets and pegging, the shape of a map texture, the file round trip,
undo, the weld, the cut, the merge, the scatters
(count, area, spacing, determinism, clumping, pillars and props, the
one-tree-to-a-cell rule, the too-dense report), the game's forest
growing exactly the placed plants, bake and move, and both doors in
and out. "the texture pack" checks the list against the files (every
name, size and scale), the runs and Doom's clock, the animator, what a
map needs loaded, the skies, the Godot sky and script, and the wiring
in the game, the editor and the site.


THE GRID

The test area, and that is all it is: a large walled-off green grid with
a crowd standing on it and every gun in the rack in your hands. At the
user's request it holds nothing else.

  js/maps/grid.js    the field, the wall and the crowd
  js/textures.js     T.GRID and T.GRIDWALL, the only two pictures in
                     this game drawn in full colour
  js/main.js         the picture, the sky and the one switch that says
                     no vehicles

WHAT IS ARCHIVED RATHER THAN GONE, because all of it comes back and none
of it was deleted. Every one of these is still in the repository, still
exported and still tested by the suite:

  the superstore and the town   js/maps/sellwrong.js, js/maps/town.js
  the fire simulation           js/fire.js, and `noCellFire`
  the burning boxes             js/boxes.js, and `boxes`, now empty
  the responders                js/responders.js, js/brigade.js, and
                                `noSquads`
  the vehicles and the gunship  js/vehicles.js, js/vtol.js, behind the
                                VEHICLES switch in js/main.js
  the lo-fi picture             js/lofi.js and js/palette.js, turned
                                down to a pass-through

Putting the world back is turning those switches over.

THE FIELD is 10,240 units square — 160 cells of 64, which is Doom's own
grid and the ruler the rest of the game is already cut to. It is ONE
RECTANGLE and four one-sided lines: about ten triangles for the entire
world, which is what a test area for guns and crowds ought to cost. The
floor used to be cut into hundreds of strips because there were boxes
standing in it and a sector here is one ring of points and cannot have
an island in the middle; with nothing standing on it, there is nothing
to cut around.

Two hundred people stand in the middle two thirds of it. A hundred over
the whole field was one person every million square units, which is not
a crowd, it is dust.

NOTHING CATCHES, at the user's request, and that is a different thing
from having no weapons. The flamethrower still throws flame and it still
hurts; the extinguisher still freezes people solid. What is gone is
anything in the world going up as a result — one flag on the map
(`noBurn`), read by Actor.ignite and Vehicle.ignite, answers every
source of fire in the game at once.

THE PICTURE IS FULL COLOUR AT THE WINDOW'S OWN RESOLUTION, and this too
is a setting rather than a removal. js/lofi.js is untouched and still
does all of it — the buffer, the block average, the ordered dither, the
palette snap, the chunky grid. What moved is the four numbers it is
handed: PIXELS off, so the grid is the buffer and the filter is a
straight copy; DITHER 0, because there is nothing to spread; SNAP 0, so
the frame reaches the screen in the colours it was shaded in; and RENDER
at the window's own row count, which is the new last rung of the render
ladder (NATIVE). Every rung of both ladders is still on the pause menu,
so the old look is three presses away.

THE ART IS STILL EARTH, which is the other half of the user's request
and a different question. Every texture and every sprite is still
PAINTED out of the 256 earth ramps — see EARTH_RAMPS. What is gone is
the SCREEN being held to them as well. The GRID box of crayons is kept
for the day the low-res look comes back; it is not needed now, because
the two pictures that actually wanted green carry their own RGB.

THE FLOOR AND THE WALL ARE THE ONLY PICTURES IN THIS GAME DRAWN IN FULL
COLOUR, and the only two drawn bigger than 64 pixels. Everything else is
a 64-square out of the palette, point sampled, and that is the whole
look. A ruled line is the one thing that does not survive it: the grid
is not a picture of a surface, it is geometry standing in for geometry,
and at one repeat every 64 units over ten thousand units of field a line
snapped to a palette and then point sampled is a stack of aliasing. So
these two are 256 square, they carry their own RGB, and they ask the
bank for the smooth filter with anisotropy. The line is a GLOW rather
than a stripe — brightness falling off as a gaussian either side of the
cell edge — which gives it a clean bright core and an edge the mipmaps
can average without it vanishing at the far wall.

THE SKY is green at the horizon, dark green through the middle and black
overhead, and now baked in full colour too: the snap in js/skyart.js is
on a dial and this world asks for none of it. The clock does not run and
the fire makes no haze, so it is baked exactly once. The air fades to a
texel of that sky (js/material.js), so the far edge of the field goes to
the same green the horizon is — the world ends rather than stopping at a
wall.


THE FIRE TRUCK  (archived — see THE GRID)


The user's fire variant of the police van: the same body and wheels on
a red sheet, with a water cannon on the roof. It is the first responder
on the side of the building. It does not put firefighters on the ground
yet; the truck is the whole brigade for now.

  assets/models/firetruck.glb   the game's copy, made by the same script:
    blender -b -P tools/blender/prep_swatvan.py -- fireTruckVariant.glb assets/models/firetruck.glb 1024 0.5 0.5
  js/brigade.js                 who calls it, how many come, where they stand
  js/water.js                   the jet
  FireTruck in js/vehicles.js   the cannon

THE FIRE CALLS IT, not you. After eight seconds of anything alight (the
store, the wood, a car), one truck is sent. Another follows every forty
seconds while the fire lasts, up to one per sixty cells alight and never
more than four. It comes up the same road and round the same ring as the
SWAT, stands as near the thickest part of the fire as the tarmac allows,
and stops 520 short of it, never on burning ground. A fire inside the
building is fought from a bay in the fire lane. Its siren is lower than
the police's, and its light bar flashes red and white.

THE CANNON LOOKS, TURNS AND POURS. About three times a second it looks for a
target. A burning vehicle comes first, because those go up; then a
burning person; then the part of the store's fire or the wood's that it
can see and that is nearest its working distance of 560, hottest first.
It avoids the patch at its own wheels. The turret slews, and the barrel
lifts to the angle that lands a jet there: aimPitch runs the jet's own
flight backwards. Once it is on target it pours, walking the jet a
little either side the way a crew plays a monitor over a fire.

THE WATER is a liquid jet: thrown fast, holding its speed, and coming
down in an arc about 1,270 units long on the flat. Where it lands it
takes heat out of the fire grid (more, over a wider patch, than the
extinguisher) and puts out trees, with steam coming off what it
cools. A drop landing by a burning car puts the car out, unless it is
already charring. Anybody it passes through is put out (Actor.soak) and
pushed along it, including you. Like the extinguisher, it cannot unburn
anything.

The truck stands in fire well: three times the squad van's fire armour
and half again its fuse.

THE POLICE VAN, AGAIN  (archived — see THE GRID)


The user's second assault van replaced the first, and it came in pieces
the game can use: four wheel nodes and a light bar on a material of its
own, `DynamicPoliceLightMatEmissive`.

  assets/models/police_assault.glb   the game's copy
  tools/blender/prep_swatvan.py      what made it
  js/bloom.js                        the light bar and the bloom off it

  blender -b -P tools/blender/prep_swatvan.py -- newSWATvan.glb assets/models/police_assault.glb 1024 0.5 0.5

The file faced -z, with its steering axle and its light bar at -z and
"wheelFrontRight" at +x, so the script turns it half a turn to face +z the
way glTF and the game both expect. It stacks the body's and the wheels'
colour sheets into one picture, since a vehicle here is drawn off one
sheet, drops the normal and metal-rough maps, and halves the triangles:
thirty thousand in, fourteen thousand out, seven of them body.

It is 240 long, 97 wide and 100 tall: a bit bigger than the 214 by 89 by
93 van it replaced.

THE WHEELS TURN. js/car.js keeps any node named wheel_* out of the body
and hangs each wheel off the body mesh about its own axle, drawn with the
body's material so it warms in the thermal sight and chars with the rest
of the van. While the van drives, each wheel turns through the distance
it rolled divided by its radius.

THE LIGHT BAR FLASHES, red on its left half and blue on its right, two
strobes a side in two-thirds of a second, with each van out of step with
the others. It is drawn unlit, goes dark when the van goes up, and shows
as warm in the thermal sight.

AND IT GLOWS: a selective bloom (js/bloom.js). After the world is drawn,
the lamps alone are drawn again at half size. Each glowing pixel is
checked against the world's depth, so a bar behind the store does not
glow through the store. The result is blurred at quarter size and added
back onto the frame before the gun is drawn, so the gun in your hands
covers the glow. Nothing else in the game is on the bloom layer, so a
white shelf label does not halo, and with no lit bar in the scene the
pass is skipped entirely.

THE QUAD LAUNCHER
-----------------

THE SIXTH WEAPON, at the user's request, and the request was one
sentence: "a quad missile launcher — use the same method as the sniper
rifle display to put a thermal scope live view on a plane in the scope
— has a heat-seeking quad shot function, can fire up to four at once
with four locks". Every part of what follows is one clause of that.

  js/missiles.js        the seeker, the salvo, the flight and the warhead
  js/thermal.js         the sight: a Scope, drawn in heat
  assets/models/launcher.glb   the XM222, the gun
  tools/blender/prep_launcher.py   what made the game's copy of it


THE MODEL IS THE XM222

The second model in this slot, and at the user's request it replaced the
first outright: "fully replace the heat seeking rocket launcher with the
new model, I've prepared a surface for the thermal display to be
projected on". It came modelled and textured — three meshes, 12,656
triangles, fourteen megabytes, seven 2048 sheets — and with the screen
already in it: a slightly domed panel on the back of the sight under a
material of its own, which the file spells dyanmic_display_surface_mat,
and so does GUNS.

tools/blender/prep_launcher.py, headless, makes the game's copy:

  blender -b -P tools/blender/prep_launcher.py -- xm222.glb assets/models/launcher.glb 1024

  - the file's node transforms baked into the vertices, and half a turn
    so the rockets' noses point +z, the way every gun here is modelled
  - the ordnance, one mesh of four rockets, split by which quarter of the
    box each loose part is in into rocket_0 to rocket_3, in the order the
    tubes fire, so a fired tube can be drawn empty (`loaded` in GUNS: with
    n rockets left, the last n are drawn)
  - the gun's and the rockets' colour sheets cut to 1024 and written as
    JPEG; the normal, metal-rough and specular maps dropped, and three of
    the four UV sets and the tangents with them, because the gun shader
    reads colour and nothing else
  - the display kept flat and under its own name, for js/thermal.js

894 kilobytes. Nothing is decimated: it was already a game model.

THE FIRST ONE was a Nomad sculpt, remeshed and baked by
tools/decimate-model.mjs and tools/bake-model.mjs, which are still here
for the next sculpt, as is the gun shader's PAINT path. It had no screen,
only a blank face on the back of its sight, so the game built one there
(`screen` in GUNS, which no gun uses now).


HOW IT IS HELD

On the right shoulder, the way the M202 it is plainly modelled on is: the
tubes running away from you in the lower right quarter and the sight on
the near front corner of the box, its screen facing you. Every number is
off the vertices: `tubes` in GUNS is the middle of each rocket's nose, in
firing order — top left, top right, bottom left, bottom right as the
gunner sees them — and the suite measures each one against its rocket.
The hip hold was picked in the running game, off three tried side by
side.

THE HOLD AT THE EYE WAS SOLVED, as the lance's was. Its turn cancels the
view's own cant, so the screen looks straight back at you; its position
is the screen's middle, in the gun's own frame, subtracted from a point
23.6 centimetres in front of the eye, where the screen is 53 per cent of
the picture's height. The suite runs the same sum.


THE THERMAL SIGHT, BY THE LANCE'S METHOD

The lance's screen is a second camera at the eye rendering the one scene
into a small target, laid over a mesh the file named for a display (see
THE POSITRON SNIPER LANCE, and js/scope.js). The thermal sight is that —
ThermalScope extends Scope — with three differences.

THE PLANE IS THE FILE'S. The XM222 has a display surface on the back of
its sight, prepared by the user for this, so `display` in GUNS names its
material, the loader hangs the thermal screen material on it, and from
there it is measured and mapped exactly like the lance's panel, u flip
and all. It is very nearly square — 0.728 across and 0.741 up — so the
feed, the canvas and the camera are too; the suite holds the two numbers
to each other.

THE PICTURE IS HEAT. For the one render call the sight makes a frame, a
shared uniform — world.thermal, in js/material.js — is on, and every
wall, floor, tree, car, puff and person that shades through the world's
GLSL answers how WARM it is instead of what colour it is. The night sits
in one narrow cold band, a little warmer for dark paint and for lamp
light; people are warm whatever they are wearing, the drawing's own
light and dark only giving the figure its shape; a frozen shopper is the
coldest thing in the picture; somebody on fire, a flame, a lamp are
white; a running engine is warm and a parked car is not; the sky is
black; smoke is almost gone, because seeing through smoke is what the
thing is for. A standee batch says whether its picture is a BODY, since
the crowd shares its draw calls with the trolleys and the headstones.
The screen runs the number up IRONBOW — black, indigo, magenta, red,
orange, yellow, white — in bands, with the lance's scan lines and curved
glass, and a missile leaving the tube beside it whites it out.

THE GLASS SAYS WHAT THE SEEKER IS DOING. Four things, since the panel is
a few dozen chunky pixels once the lo-fi pass has it: the seeker circle,
drawn at the true size of the cone for the magnification it is at; an
amber bracket on every locked target, with a pip in the corner for every
lock past the first; a white one closing in, blinking, on what is being
acquired; four tube pips — loaded, empty, or spoken for by a lock — and
the lock count, big, at the top.


THE SEEKER AND THE QUAD SHOT

HOLD THE TRIGGER and the seeker looks for heat within six degrees of the
middle of the view, out to the far side of the town. What is warm, in
plain sight and nearest the middle is acquired — sixteen tics of dwell
for the first lock and eleven for each after — and then locked, and it
goes on to the next warm thing in the circle, up to four, one per loaded
tube. With fewer warm things in the circle than tubes it locks the same
one again, so four locks on one gunship is four missiles into one
gunship. Once the dwell has started it follows the target through a
circle twice as wide, because an aircraft crossing the sight leaves a
six-degree circle between two corrections of your hand. A lock survives
half a second out of a much wider cone or out of sight, and not at all
if its target dies or goes cold. WHAT IS WARM is answered in one place,
MissileSystem.isHot, and the thermal sight asks the same function, so
the screen cannot glow on anything the seeker would refuse.

LET GO and one missile leaves per lock, a tube at a time, four tics
apart — top left, top right, bottom left, bottom right — kicked outward
by where its tube sits in the box, so a salvo fans out before it turns.
With nothing locked, letting go fires one straight down the sight: a
launcher that did nothing without a lock would be the bore.

THE FLIGHT. Twelve units a tic out of the tube to fifty-eight, over
twice the gunship's best; five tics before it steers, then no more than
0.085 radians a tic at where the target WILL BE, led by its own velocity
over the time left to fly. It stops for walls, floors, ceilings, its
target and anybody standing in the way, and after seven seconds wherever
it is. A lick of flame every tic off the fireball pool is the streak you
watch it by, and the motor pulls the one fire light along with it.

AND IT IS A ROCKET YOU CAN SEE, at the user's request: "whatever rocket
sprites you make need exhaust and smoke trails and an impact
explosion". The body is ROKT, drawn by the program like everything else
in the rack — an olive tube with a yellow band, a grey nose, four swept
fins, a flame out of the nozzle in two flickers — and drawn from eight
sides, like a Doom thing, because a rocket crossing the view is a long
thing and one coming at you is a nose and a ring of fins. Which of the
eight is where it is heading against where you are standing
(rocketFacing). The motor's bloom, MISL, rides behind it, additive.

THE TRAIL is its own pool of puffs and not the store's smoke, which is
dark — it is the smoke of a burning aisle — and at night could not be
seen at all. This one is born pale and warm, lit well above the street,
goes grey as it spreads, and drifts off on the wind. It is laid along
the leg the rocket flew each tic, a puff every fourteen units, rather
than where the rocket ended up: at fifty-eight units a tic, a puff a tic
is a dotted line.

THE BANG is MEXP, eight frames of fireball, three tics each and three
metres across — a white core going orange, a torn shock ring in the
first three frames, sparks thrown clear, and then holes eating in from
the edge as it burns out — with four of the aircraft's fireballs in it
for the glow, and embers. THE SMOKE COMES AFTER THE FIRE: the first cut
put the whole cloud down at the instant it went off, and smoke is drawn
after anything solid, so eight dark puffs sat in front of the fireball
and all that showed of the explosion was its shock ring. The cloud now
starts as the ball starts to burn out, a puff a tic, each higher than
the last. And what it hit is marked: the hot spot a flame leaves on a
wall or a floor, at its hottest, cooling to a scorch.

THE WARHEAD. 420 to what it flew into, up to 150 to anything within 190
units, as a BLAST and never as fire: Game.explode deals fire, and the
SWAT and the army are fireproof, so a warhead built on it would have
walked through a trooper. 420 is a quarter of the gunship and a little
over, so a full salvo of four locks brings it down, which was checked in
the running game against one hovering two and a half thousand units
out. It starts a fire where it goes off, and it reaches you too if you
are standing in it.

THE TUBES LOAD THEMSELVES, one every two seconds, so a full salvo is back
in eight — fast, because what rations this weapon is the second and a
half of standing still with it up while the seeker works.

The sounds — the seeker's growl, the lock pips, the launch — are in the
synthesised table and so are silent while MUTED is on, like everything
else in it; a recording under the same name would take over.


THE ARC MAW
-----------

THE SEVENTH WEAPON, at the user's request, and the request was the
design: "between the three prongs on the business end a lightning bolt
will come out and chain-arc up to 9 people, with field effect damage
for people nearby, lots of trailing falling particle effects, hit
particle effects, charging is a thing too where blue energy particles
will gather in the weapon's maw generating an ever growing blue energy
ball, more charge = more chain hits".

  js/arc.js             the lightning: who it strikes, the field, the
                        bolts, the sparks and the drips
  assets/models/arcgun.glb   the gun, finished in Blender
  tools/blender/        the headless Blender scripts: three did this one —
                        the bake, the full textured export, and the
                        game's copy. Blender is not needed to run or
                        test the game — only to rebuild the model


THE MODEL WAS A SCULPT, AND ITS SURFACE WAS A NORMAL MAP

The user's second Nomad file: ninety-one thousand triangles, a colour
sheet that was plain white, and every rib and panel and glyph on it in
a four-thousand-pixel normal map that nothing in the file even used. So
it was finished in Blender, run headless, at the user's request: the
normal map hooked up; the ambient occlusion baked THROUGH it, so the
sculpted relief shades its own cracks, and a curvature map made from
the mesh's own shape and the normal map's detail together; and on top
of the two a distressed gunmetal built out of nodes — dark steel, rust
and grime settling where the occlusion is deep, edges worn to bright
metal where the curvature is sharp, scratches, a few patches rusted
through — baked down to a sheet. The textured model went back to the
user as it was, normal map and all.

WHAT SHIPS IS A GAME'S COPY of it: cut to sixteen thousand triangles by
Blender's own collapse, which keeps the UVs, so the baked sheet still
fits; the file's node — a quarter turn and a lift — baked into the
vertices and the prongs' axis put on x = y = 0, so the maw is (0, 0, z)
in the units GUNS speaks in; and one sheet with the occlusion and the
relief MULTIPLIED into the colour, because the gun shader here reads
colour and nothing else, and a relief nothing lights is a relief nobody
sees. 705 kilobytes, a thousand-pixel JPEG. Where the maw is was found
by rendering the model from the side and down the barrel with a marker
at the candidate point, not by reading numbers off a list of vertices:
the first guess ignored the node's turn and sat in mid-air.


THE CHARGE

HOLD THE TRIGGER and it charges, from nothing to full over three
seconds, and stays full as long as you hold it. What you see is the
gun's (js/weapon3d.js, `orb`): a white-hot core in the maw between the
three prongs, a blue halo that breathes round it, both growing with the
square root of the charge, and motes of blue energy born on a shell
round the prongs and falling into the middle faster as they near it —
more of them, and from further out, the higher it goes. All of it is
drawn in the gun's own scene, so the ball is in the maw however the gun
moves and never behind a wall the barrel is poking through. What you
hear is a hum struck again every few tics, a step higher each third of
the way up, and a whine as it tops out.


THE DISCHARGE

LET GO and it goes. The first strike is whoever is nearest the middle
of the sight, inside nine degrees, in range and in plain view; with
nobody there the bolt goes straight down the sight into whatever stops
it, and grounds with a scorch. From each body it hops to the nearest
one it has not struck yet, within 560 units and in plain view of the
last, until it has made its count — ONE FOR A TAP, NINE AT THE TOP OF
THE CHARGE, hitsFor(charge) — or has nobody left to hop to. The chain is
chosen whole when the trigger comes up and REVEALED a hop a tic, so the
eye can follow it across a crowd, and each strike lands as it arrives:
48 off a tap and 190 off a full charge, each hop a twelfth less than the
one before.

THE FIELD: everybody standing within 150 units of a strike who is not
in the chain takes up to four tenths of it, less the further out they
are, with a short arc drawn to each of them to say so.

SUB-BOLTS, at the user's request: "sub bolts too, thinner branches at
random, might generate bonus kills". Every strike down the chain may
throw thinner branches off itself — a third of the time off a tap, four
times in five off a full charge, up to three at once. Each reaches for
somebody within 430 units the chain passed over, picked AT RANDOM from
everybody in reach and in view rather than the nearest, so they spray,
and deals a little over half the strike; a kill that way is a BONUS
KILL, and ArcSystem counts them. A branch with nobody to reach for
grounds into the floor a little way off. They are drawn thinner than
the chain, with a fork of their own, and shed their own drips.

IT IS NOT FIRE. Damage that is not fire is what the fireproof SWAT and
army feel, and it shatters anybody frozen solid, which is what a bolt
through a block of ice should do. AND A BOLT KILLS WITHOUT BURSTING: a
strike is held to what the body has left and a little over, because
the game reads damage far past zero as a body coming apart, and a
trooper under a nine-man chain was coming apart in gore. A shopper
still goes off the way a shopper always does — that is their only
death in this game.

WHAT YOU SEE: every link a jagged line of light — midpoint displacement
off a seed, fixed at both ends and widest in the middle — re-cut every
other tic so it crawls, a wide blue glow under a white core, with forks
off it; and thinner near your eye, the tracers' rule, or the first link
out of the maw is a white wall over half the picture. A burst of light
and sparks at every strike. AND THE DRIPS: hot blue sparks shaken off
every lit link and every strike that fall, bounce once off the floor,
and leave a mote behind them every tic all the way down, which is the
trailing, falling rain the request asked for.

THE CAPACITOR holds six discharges, whatever each was charged to, and
refills one every three seconds: what a nine-man chain costs is the
three seconds of standing there with the ball growing. Empty, the
trigger clicks.


A HOLE BLOWN THROUGH A WALL
---------------------------

At the user's request: "any structure in the path of the beam has a hole
blown through it, the hole will then decay into debris and burning".


IT IS NOT A DECAL
-----------------

The game already has a decal system and a very big scorch on a wall
would have been half an hour's work. It would also have been a PICTURE
of a hole: you could not see through it, shoot through it or walk
through it — and the first thing anybody does after firing a
two-hundred-unit column of plasma through the front of a house is walk
into the house through the front of it. A hole that is only a picture is
a lie that is found out immediately.

So it is geometry. A wall in this game is a LINE (js/level.js) drawn as
a quad spanning its length at some interval of height, and a hole is the
statement that a RECTANGLE of that quad is no longer there. js/breach.js
is that statement and the arithmetic of it.

THE COORDINATES ARE (t, z): how far along the line as a FRACTION of its
length, and world height. The first of those because js/mapgeo.js's
addQuad already took exactly that as `span` — it was put in so the wall
under a gable could be drawn in the two pieces either side of the ridge,
with the brick still reading as one length across both, and a hole is
that same idea asked in two axes. The second because every other height
in the engine is world units and a hole has to be comparable with a
floor, a ceiling and a player's eye.


PUNCHING MERGES RATHER THAN APPENDS
-----------------------------------

The beam punches on its structural clock, a dozen times a second, for
the whole of its discharge: a wall the column sits on would collect
sixteen rectangles, all of them nearly the same rectangle. So a
punch that OVERLAPS what is already gone grows that hole to the union
instead of adding to the list — cheaper, and truer, because a wall does
not get two holes where one beam crossed it, it gets a bigger hole.
Eighty punches at the same place are one hole; forty punches in forty
places are four, because the list is capped and past the cap a new punch
grows the NEAREST hole rather than being dropped. A wall that has been
shot at all day ends up with a few large holes rather than a hundred
small ones, which is what a wall that has been shot at all day looks
like.

And growing one hole can bring it into contact with another, so there is
a second pass: two holes that touch are one hole. Without it a wall
crossed twice keeps two rectangles sharing an edge, and the grid below
then cuts a zero-width column between them.


THE SPLIT IS A GRID, WHICH IS THE WHOLE TRICK
---------------------------------------------

"Draw this rectangle except for those rectangles" is an awkward problem
right up until you stop trying to be clever about it. Take every hole
edge that falls inside the wall, cut the wall along all of them in both
axes, and you have a grid of cells each of which is ENTIRELY inside a
hole or entirely outside one. Test each cell's middle, keep the
survivors, merge each row of survivors back into runs.

It is exact, and it is checked as exact: the pieces plus the holes come
to the wall's area to the last decimal place, for one hole and for two.
A wall with one small hole in it is twelve quads; a wall crossed by a
column taller than itself is four — two strips of brick either side and
two of scorch.


THE EDGE IS CHARRED AND THE REST OF THE WALL IS NOT
---------------------------------------------------

The first cut charred every surviving piece of a breached band, on the
argument that brick which now ends at a hole ends at a burnt edge. It
does — but a piece can be forty metres of shopfront whose far end has
never been near the beam, and charring all of it because the near end
was is a building that goes black because somebody shot a window.

So there is a second set of cut lines a rim's width outside each hole,
and a cell TOUCHING a hole is its edge and is burnt while a cell beyond
that is not. A row merges only while the answer stays the same. What
comes out is a scorched border about a foot wide round the opening and
clean brick past it.

The rim is measured in WORLD UNITS in both axes, which is the point,
because one of the two axes is a fraction: a rim written as a fraction
of the line is thirty-five centimetres on a shopfront and four on a
garden wall.


AND THE HOLE IS REAL FOR EVERYTHING, NOT JUST THE RENDERER
----------------------------------------------------------

  walking   Level.lineBlocks asks whether the mover's own span at the
            crossing is inside a hole, across their WHOLE WIDTH and not
            just under their middle — a body is a circle, and a hole
            narrower than the body is a hole you walk into. Three
            samples, the middle and both shoulders.
  shooting  Level.rayHitWall passes through, so a round follows the beam
  seeing    Level.sightBlocked passes through, so a shopper on the far
            side of a breached wall is in view and knows you are there

WHAT A HOLE DOES NOT EXCUSE is a floor or a ceiling. The other refusals
in lineBlocks — too low, too high, too far — are about the two REGIONS'
own heights at the crossing, and a hole in the brick between them says
nothing about either. Blowing the front off a house does not lower the
landing behind it, and a breach that excused "too low" would let you
walk through the gap over a door and out into the air above the hall.


FINDING THE WALLS
-----------------

Level.rayHitWall is the obvious tool and is wrong twice over: it returns
the FIRST wall and stops, and the whole point of this weapon is that it
does not stop. So the column's segment is marched through the blockmap
instead — a small box every 128 units, deduplicated — and every line
that actually crosses it is punched. A shot across the town opens ninety
walls in two milliseconds, which is fast enough to do a dozen times a
second for five seconds.

HOW WIDE THE HOLE IS is not the column's diameter. A cylinder of radius
R crossing a plane at an angle cuts a chord of 2R/sin(angle), so a beam
that grazes a wall at ten degrees cuts a hole six times its own width —
which is right, and is also why it is capped at three and a half: at one
degree the chord is the whole street, and a shot fired ALONG a terrace
should not delete the terrace. A column exactly parallel to a wall never
meets its plane and is skipped.

AND ONLY WALLS. A two-sided line between two patches of street draws
nothing and is not a structure; giving it a breach list would put one
more property read into the collision, the bullet ray and the sight line
for every query for ever, in exchange for a hole in nothing.


AND THEN IT DECAYS
------------------

A fresh breach is a clean cut through brick. Over three seconds it does
three things:

  it crumbles   the opening grows in three discrete jumps — discrete
                because every change to a hole rebuilds the block it is
                drawn in, and a smooth grow is a rebuild every frame
  it sheds      debris falls out of the widening edge and the dust of it
                hangs at the foot
  it burns      the fire grid is lit at the hole, so the opening goes on
                burning by itself and the region round it chars on the
                fire's own clock

AND IT TAKES A BITE OUT OF ITS OWN EDGE, which is what stops it being a
rectangle. A hole that only grows stays a rectangle however far it
grows, and a rectangle is a window. So each crumble also cuts a small
step into one SIDE of the opening at a height that is not the middle —
sideways always and never up or down, because the column is usually
taller than the wall it crosses and a chip above the hole lands in the
sky. The sides are where the brick still is.

The clock stops after three seconds. A hole that grew for ever would eat
the building, and the building coming down is a different question with
its own answer — see FireSystem.damageLine, which takes integrity off
whole REGIONS. The two are not the same thing and are not meant to be: a
beam through the front of a house leaves a hole in the front of the
house long before the house comes down, and usually instead of it.


A TUNNEL OF DEBRIS ROUND THE HOLE
---------------------------------

At the user's request: "build a debris tunnel around the hole ... that'll
make it look really convincing like the lance just like tore through the
structure".

A rectangle cut out of a wall is a rectangle cut out of a wall. What it
is missing is THICKNESS — a real wall is a foot of brick and a hole
through it has an inside, and the reason a cut-out quad looks like a cut
-out quad is that its edge is a line with nothing behind it. So the edge
gets geometry: js/ruin.js's breachDebris hangs a ring of chunks round
every opening, standing out of the wall on BOTH faces, which is what
makes it a tunnel rather than a wreath.

THE PERIMETER IS WALKED AS ONE LOOP and a chunk's place on it is one
number from zero to one. That is worth more than it sounds: the corners
then look after themselves, and the density stays even on a hole that is
much wider than it is high — which every hole this weapon makes is,
because a beam raked across a shopfront takes out a band. Up to sixty-
four chunks depending on the perimeter, six per hundred units of edge,
at sizes from four units to thirteen.

THOSE THREE NUMBERS ARE A PHOTOGRAPH'S WORTH OF CORRECTION. The first
cut put two and a half chunks per hundred units at sizes up to
twenty-two, standing twenty-six units off the wall, and what a picture
of it showed was not a tunnel: it was half a dozen slabs the size of
garage doors hanging in the air a foot away from a house. A wall in this
engine has no thickness of its own for debris to be continuous with, so
anything standing that far off it is plainly floating. More of them,
smaller, and hugging the brick — and the ring reads as the wall's own
edge coming apart, which is what it is.

AND THE RING IS CLAMPED TO THE WALL. A hole is a rectangle in (t, z) and
nothing ever made one stop at the top of the brick: a two-hundred-unit
column fired at head height through a single-storey house punches from
under the floor to well over the eaves. js/mapgeo.js only ever DREW the
part inside the wall band, so nobody had noticed — but a ring walked
round the whole rectangle put a third of itself in the sky above the
roof, which the same photograph showed. The caller passes the storeys
that are still standing, floor and ceiling in pairs, and the ring is cut
to whichever of them the hole mostly took.

THE SAME LIST OUTLIVES THE WALL, which is the other half of that rule. A
region that collapses stops drawing its brick — its floor meets its
ceiling and the quad has no height — but it keeps every rectangle ever
punched out of it. Debris hung off that list without asking is a ring of
masonry in mid-air over a pile of rubble, and a beam fired down a street
brings houses down behind it, so this was not hypothetical. A hole with
no standing storey left is not dressed at all.

WHICH STOREYS THOSE ARE HAS TO BE THE WALL'S OWN ANSWER and not the
sectors either side of it. The first attempt took floor and ceiling off
both columns, which for a house front means the room inside AND THE
STREET OUTSIDE — and the street's ceiling is the sky a few thousand
units up, so the band with the most overlap was always the open air and
nothing was ever clamped. A two-sided line already carries the intervals
it draws brick in: l.bands, the uppers and lowers, which is how a
shopfront gets three bands of masonry with two ribbons of glass between
them. Those are the bands. One-sided walls, which have no such list, are
the whole storey.

AND A KERB IS NOT A WALL. Most of the lines in a street are twelve-unit
risers at the edge of the road and thirty-two-unit steps up to a
forecourt, and a beam cuts every line it crosses. A hole punched through
a kerb is invisible and always was; a ring of debris hung off one is
broken masonry lying along the gutter for the length of the block, which
is exactly what the next photograph showed. Twenty-four units — about
knee height — is the shortest piece of wall with anything to tear
through.

EACH CHUNK IS AN ORIENTED BOX and not an axis-aligned one, which is the
only new geometry in the file: every other builder in js/ruin.js makes
boxes square to the world, and these have to lie square to the WALL — a
chunk of a wall that runs north-east does not point north. Five faces
from three vectors: along the line, out of it, and up. The sixth is
inside the wall and nobody sees it.

THEY HANG INWARD. Each is pulled between a tenth and a half of the way
toward the middle of the opening, because what is left round a bored
hole hangs INTO it — a clean ring standing off the rim reads as a
picture frame. And they alternate sides down the loop, so from either
face you see stubs coming at you and, through the gap, the far side's
stubs going away.

The lighting is the region's own, jittered a third either way, and the
chunks are RUBBLE in the same batch set as everything else the ruin
builder makes, so a hole costs no extra draw call: a wall with a hole in
it is one hole's worth more geometry in a batch that was being rebuilt
anyway. Measured: twelve chunks and sixty quads for a single opening,
eighteen for two.

AND IT IS ALREADY ON FIRE, because breach punching calls fire.ignite at
the hole's own place as it cuts, so the burning that the user asked for
next to this is the game's existing fire finding a new edge to sit on
rather than a second system pretending to be one.


BUT A WALL THAT IS GONE WAS HOLDING SOMETHING UP
------------------------------------------------

For a while those two questions were not connected at all, and it
showed. A beam raked along a terrace took the ground floor out of the
whole row and left the upper storeys and the roofs hanging in the air
over nothing, because no cell of the column had been near enough to the
middle of any of those regions to spend their integrity — the regions
were fine, and only their walls had gone.

So taking a wall out now costs the regions it belonged to, in proportion
to how much of it went. A graze that opens a tenth of a shopfront is a
hole in a shopfront. A column that takes a whole wall takes most of a
region's integrity with it, and a shot THROUGH a building is two walls,
which is a building coming down. Along one is a hole.

Once per wall, on the first punch, because cut() runs a dozen times a
second for the length of a discharge and a bite per pass would flatten
the town.


THE REBUILD IS BY LINE AND NOT BY REGION
----------------------------------------

Game.markBreached exists beside _markDirty for one reason: a region is
drawn in the block its middle lands in and a line is drawn in the block
its MIDPOINT lands in, and the two are not always the same block — see
the note in js/mapgeo.js about the wood owning the supermarket's flank.
Marking the region would rebuild a block that does not contain the wall.

And the FIRST punch of a burst sets the clock, not each of them. A beam
punches a dozen times a second and a rebuild scheduled afresh by each of
them is a rebuild every tic for five seconds; once the rebuild has run
the flag clears and the next punch starts a new wait, so the holes
appear in steps of about a third of a second for as long as the column
is out — which is to say, while you watch.


ONE DEATH SCREEN, AND EVERY DEATH GETS IT
-----------------------------------------

At the user's request: "all death screens should be YOU DIED in red, in
Japanese, red text, black box, red filter on the game field".

What it replaces is a line of amber type reading YOU DIED IN AISLE 5,
drawn by the same routine as every other notice. That was the right card
when a supermarket was the whole game; it has been wrong since the town,
and it was the only thing left that announced the end of a run.

THE BOX IS A BAND AND NOT A PANEL. Full width, a fixed share of the
height, hard edges, a red hairline top and bottom and nothing else. A
panel with a border reads as a dialogue you are meant to click; a band
reads as the picture being taken away from you, which is what has
happened. Eighty-eight per cent black, so the world is still faintly
there behind it.

IT SAYS IT TWICE: 死 in red above, YOU DIED in red under it. The kanji
means death by itself, which is why it is the one on a seal and not 死亡
or a sentence. It needs a face that HAS it — the page's own face is a
monospace stack and none of those carry CJK, so the character would come
out as a tofu box on most of them. The usual ladder, ending at the
generic serif, which on any system with a Japanese font installed
resolves to one. And how to go again is still on the card, small,
because that is an instruction and not an announcement.

AND THE PICTURE BEHIND IT GOES RED. That half lives in the tint over the
world rather than on the readout, because it belongs to the picture. It
is on for EVERY death now, including the one the camera leaves the body
for — which reverses what that line said a release ago, when the veil
was taken off the third-person death on the grounds that a veil is what
dying looks like from inside the body. True, and the user has asked for
one filter over every death, and a consistent one is worth more than the
distinction. What was actually wrong the first time was the STRENGTH:
0.35 of flat red hid the crater, which is the one thing that death is
for. At 0.26 it reads as a filter and you can still see what you did
through it.


THE READOUT CAME OFF THE PICTURE
--------------------------------

At the user's request, and it is a line about what a thing IS rather
than about how it looks.

For most of this project's life everything drawn over the world went
into the same low-resolution buffer as the walls: the same chunky pixel
size, the same ordered dither, the same snap to two hundred and fifty-six
colours. The argument was good and it is still in js/lofi.js — a crisp
modern overlay on a chunky world reads as a filter applied to a
photograph, and one frame of it undoes what the renderer is doing.

THAT ARGUMENT IS RIGHT ABOUT THE PICTURE AND WRONG ABOUT THE READOUT.
The gun in your hands is IN the room. It is lit by the room, it moves
with your step, and a crisp gun over a chunky shop is a cardboard cut-out
held up to a photograph. The numbers are not in the room. Nothing
occludes them, nothing lights them, they do not move when you move: they
are printed on the glass, and a label on the glass is not more honest for
being out of focus. A six-pixel bitmap face, doubled, averaged down onto
a grid three hundred and twenty pixels wide and then quantised to the
nearest of 256 colours is four separate things happening to a word whose
only job is to be read at a glance.

SO THE SPLIT IS BY WHAT A THING IS, not by which file it was in, and
js/hud.js is now in two halves that live on opposite sides of the filter.

  THE PICTURE HALF stays exactly where it was: an overlay scene handed to
  the pipeline, filtered and dithered and snapped with the walls. Two
  things are in it. The WASH — the few frames of gold on a pickup, the
  red when something hits you — because that is a thing that happens to
  the photograph and it should be made of the photograph's colours. And
  the FALLBACK GUN, the flat sprite shown only on the day the 3D model
  does not load, because it is the gun and the gun is in the room.

  THE READOUT HALF is a 2D canvas over the frame at the device's own
  ratio, and the pipeline never sees it. Real type, real anti-aliasing,
  real colours. On a 3x phone the bars and the words are drawn at 3x
  while the shop behind them is 288 pixels across, which is the whole
  point and looks like the point.

IT IS MEASURED IN THE WINDOW'S OWN PIXELS NOW, which is the part that was
an actual bug rather than a taste. The readout used to be laid out in
CHUNKY pixels — six glyph pixels meant six of the pixels you can see — so
turning the PIXELS dial DOWN made the bars and the letters GROW. A
readout that changes size when you change how the world is drawn is a
readout tangled up in the renderer's business. Its size comes off the
height of the window and nothing else, and the smoke test lays the same
window out at 288x120 and at 1707x960 and checks it gets the same
readout.

AND IT HAS ITS OWN BOX OF CRAYONS, which is the other half of being
decoupled. The art palette is a setting and the display palette is
another; a readout drawn out of the fifteen material ramps would go muddy
when the world did, for no reason, because the readout is not made of any
material. So it has fixed colours named for what they MEAN — burn, full,
low, empty, the three layers of you — and they are the page's own: the
amber the pause menu highlights with, the bone its body text is set in.
The readout is the same readout in every box.

WHAT IT LOOKS LIKE. A dark track with a hairline round it so a bar has an
edge on a pale floor as well as a black one, rounded ends, a little
gradient down the fill so a full bar is not a flat block, a soft bloom off
the lit end, and a drop shadow under the lot. The weapon's name in the far
corner in letter-spaced caps over a short amber rule. The end-of-night
card centred, its first line amber and large and the rest dim and small.
No words in the left corner: that was asked for, and a better face is not
a reason to put the plate of numbers back.

AND IT IS CHEAPER THAN WHAT IT REPLACED. The old readout rebuilt a
pixel buffer and uploaded a texture whenever a value moved — and then, on
top of that, every one of its texels went through the block average and
the palette search EVERY frame, moved or not. The canvas is redrawn only
when something on it has changed, which on most frames is nothing, and
the frames where it does redraw cost about fifty canvas calls.

THE PAGE IS WHERE IT LIVES: a canvas in index.html inside the frame, over
#view and under the thumb controls and the menus, taking no pointer
events, and smoothed where the picture under it is explicitly not.


THE WEATHER IS A ROW multiplied over the hour's: clear, overcast, rain
and mist. Each says how far the air lets you see — WHICH IS THE DRAW
DISTANCE, because past where the air is opaque there is provably
nothing to draw, so the far plane, the crowd's cull and the wood's
range all follow airFar in, and bad weather makes the frame CHEAPER,
which means the cost ceiling to measure is a clear night — how much
of the hour's sky survives the cloud, how much cloud there is and how
dark, whether the sky is one flat colour to the zenith, a wind, and a
haze the air adds to the sky itself, because night mist is GREY and
not black, being lit by every lamp in the car park, and the first
screenshot of night mist was a black sky over a car park with the far
cars simply gone.

THE WIND WAS WIND_X = 0.28 in js/effects.js, read by three smoke
emitters and nothing else, under a comment that said the forest leaned
with it, which it did not — the wood had its own fixed pair. It is a
vector everybody reads now: the smoke, the rain's slant, the wood's
fire and the store's fire, as four multipliers on the four directions
a cell can light, so a fire runs downwind and creeps against it. ON
CELLS UNDER THE SKY ONLY. The first cut leaned every fire in the
building, and the squad's night in the test — which no weather touches
— came out with five wrecked vans instead of one and a spawn that
stalled. There is no wind in aisle six.

RAIN FIGHTS THE FIRE, which is the only reason weather earns its place
in a game that is about watching one thing burn. Two thousand streaks
in one draw in a box round the eye (js/rain.js), spawned only where
the sector has the sky for a ceiling, dying at the floor, leaning with
the wind, shaded like everything else so a drop in front of the fire
is lit by it. And on the fuel grid: a cell under the sky loses heat
faster than its fuel can put it back, so a burning car park in the
rain goes out with its fuel still in it and never lights a neighbour;
and the ember clock is cleared, which is the difference between a fire
that is out and one that is sulking. IT DOES NOTHING UNDER A ROOF,
UNTIL THE ROOF GOES: a gutted region is a region the rain gets into,
so burn the roof off a store and the weather starts putting the rest
of it out. The headless check lights the same match on the same roll
dry, in the rain under a roof, and with the roof gone: the first two
burn identically, to the tic, and the third is out in nine seconds.

THE ROLLS CAN BE SEEDED NOW — pSeed in js/util.js — because a
comparison of a fire dry against the same fire in the rain is a
comparison of nothing if the dice differ. It exists for the test.

THE WEATHER A FIRE MAKES. A town alight from end to end puts a lid of
brown smoke over itself, and this is the one thing the sky did not do:
the smoke was a fog uniform keyed to how much of the shop had gone, and
the sky over a burning town was the same clear night it started with.
Now there is a fifth weather that comes on by degrees over whichever of
the four is running. `Weather.smoke` is 0..1, how much of the sky the
fire has; it follows what is alight RIGHT NOW — the two fires' hot cell
counts, three hundred and twenty in the town or two hundred in the wood
for a full sky — with a time constant of forty seconds coming and a
hundred and fifty going, and what has already burnt holds a floor under
it, because the smoke of a town that has burnt does not blow away in the
time this game lasts. sampleFrame folds it over the frame: the zenith
goes the colour of a paper bag and the horizon the colour of the fire
under it, the sun goes red and its glow spreads, the cloud cover closes
and the stars go out, the sky's light halves, the air closes in from
fourteen thousand to twenty-four hundred and from twelve hundred to two
hundred and twenty, and the wind doubles, because a fire makes its own.
The bake sees the number and re-bakes as it moves; the fog reads the
horizon it baked; the far plane follows the air in, so a sky full of
smoke is cheaper to draw than a clear one, which is the right way round.
It is read off `climate.smoke` by anything that wants to know, and the
corner readout says SMOKE where it said CLEAR.


WHAT YOU CAN SEE
----------------

There was no occlusion culling. The frustum kept what was in front of
you, and what was in front of you, from the stockroom, was the whole
car park through two walls: seven hundred billboards culled by an
eighty-degree cone, and every chunk of wood within range.

THE MAP IS REGIONS JOINED BY TWO-SIDED LINES, and a two-sided line is a
portal — an opening between two rooms. A region can be seen if you are
in it, or if you can see it through an opening of a region you can
see, and that is the whole algorithm (Level.visibleSectors in
js/level.js). Build's renderer did it in 1996 and the data model here
was already its input: start in the region under the eye with the
field of view as a window of angle; for each opening of the region,
take the angle it spans from the eye and cut it to the window; empty
means nothing through it can be seen, so stop; otherwise the region
beyond is visible, and the flood goes on into it with the NARROWED
window. A one-sided line is a wall and not an opening, and that is the
entire occlusion test. Occlusion is not computed here. It is the
absence of a portal.

THE WINDOW IS A HORIZONTAL ANGLE, not a screen rectangle. Everything
that hides anything in a sector world is vertical, so an interval is
enough, and an interval is two numbers and a compare. It is
CONSERVATIVE, and conservative the safe way round: an opening only
visible above or below the window still lets the flood through, so it
draws things it need not and never hides a thing it should have drawn.
A region reached through several openings keeps the hull of them and
is walked again only when a new opening widens it, and after a few
widenings it is handed the whole window and left alone — which is
what stops the car park's hundreds of openings each re-walking the
lot. A region seen last frame counts this frame too, so nothing pops
the instant a doorway's edge crosses it.

WHAT IT COSTS is proportional to what you can see, once a frame: half
a millisecond from the car park into the store, nothing from the
stockroom. WHAT IT BUYS: the crowd asks it before the cone (a standee
in a region you cannot see into is not drawn however squarely you face
the wall), the wood asks it for every chunk (nine points across the
chunk, and a chunk none of whose points is in a visible region is not
drawn, whichever LOD size was picked), and the fire's sprite pool asks
it before sorting. From the stockroom with its door shut it draws the
stockroom: 98 draw calls where the cone left about five hundred.
Facing the wood from the car park, 179, the store behind you gone
entirely. Facing the store from the car park it was still nine hundred, because
you could see seven hundred shoppers through the glass and every one of
them was a draw call — which was a different problem, and is dealt with
under A CROWD IN ONE DRAW CALL PER PICTURE. It is two hundred and forty
now.

THE TEST CASTS RAYS AT IT. sightBlocked already walks a real ray, so
from five standing positions, every hundredth of a radian across the
field and every forty-eight units out to six thousand, a region a ray
reaches has to be in the flood's set — eighty thousand ray points,
zero misses — and then the other half, without which the first is
worthless: from the stockroom the set is one region, from the car park
facing the wood it is fourteen of 327 and none of them indoors, and
raising the stockroom's door takes it from one to fourteen.

AND THE FLOOD NOW CULLS WALLS. The level's geometry used to be one
batch per texture for the whole map, which gives every batch a bounding
sphere the size of the world and a frustum that never fires. A batch is
one texture IN ONE BLOCK of 3648 now, the flood's visible regions
decide which blocks are submitted, and a block's INDOOR surfaces are a
group of their own that comes in at two block pitches — which is the
LOD ladder, and it stopped being meaningless the day there were
buildings. See THE BLOCK IS THE UNIT OF DRAWING in js/mapgeo.js.


THE TOWN
--------

A strip mall in a wood is a firebreak with a shop in it. You burn one
building and then you burn some trees: the car park is two hundred and
eighty units of tarmac and the ring road is another three hundred, and
for a long time nothing crossed either. That was the ceiling on the
whole game and it is gone. There is a town on the other side of the
road.

Five by five blocks of 3072 on a pitch of 3648 — 588 metres, a bit over
a third of a mile, which is a small town's whole built-up core. The plan
is TOWN.txt and it is worth reading for the one fact that made the rest
of it cheap: THE MALL WAS ALREADY ON THE GRID. The clearing is 14,000
across and four block pitches less one street is 13,968; it is 6,992
deep and two pitches less one street is 6,720. The supermarket, its car
park and its ring road are a four-by-two superblock on a grid nobody had
drawn, to within thirty-two units. Nothing had to be reconciled with
anything.

Main Street is 1024 where every other street is 576, and its centre
lands on 2112 against a supermarket entrance at 2140. From the far end
of the town the street points at the doors, which is what a street like
that is for and is also what happened when the arithmetic was done.

THE STREET IS FIVE BANDS: 144 of sidewalk, 24 of verge, 240 of
carriageway, and the same back out. The sidewalk is three times what the
plan asked for and the kerb, at 24, is twice — both at the user's
request, and both taken out of the carriageway rather than out of the
street, because 3648 is the pitch that puts the supermarket's clearing
on the grid and a wider street would take it off. What goes is the
on-street parking; nothing was parked on it. Twenty-four is exactly the
tallest step the engine will let anything walk up, which makes a
sidewalk the highest thing in the town you can still get onto and is a
number worth saying out loud rather than finding.

A SECTOR IS A COLUMN OF STOREYS
- - - - - - - - - - - - - - - -

Doom's model has one floor at any x,y. `Level.sectorAt` returns one
sector and `Actor.setSector` says `this.z = s.floor`, and a townhouse
with a bedroom over a kitchen cannot be expressed in it at all. So a
sector may name the sector ABOVE it, over the same polygon:
`mb.column(poly, [ground, first, second])` is three sectors sharing one
outline. Every sector that existed before was already a column of one,
so the store did not change by a character.

AND A WALL IS WHERE TWO COLUMNS DISAGREE. Doom had two sectors on a line
and therefore two surfaces and called them the upper and the lower. With
columns there can be three storeys on one side and open air on the
other, and the honest statement is: take the open spans of each column;
the wall is every interval of z where exactly ONE of them is open; where
both are open is a hole and where neither is there is nothing to draw.
The texture comes from the column that is SHUT, which is Doom's own rule
about whose face a step is, said so that it survives having more than
one thing to be raised above.

Run that over a column of one against a column of one and the upper and
the lower fall back out of it. That is checked rather than asserted: all
six hundred-odd two-sided lines of the supermarket come out with the
same textures and the same quads they had before any of this, and the
smoke test holds it there.

Collision, sight, hitscan and the portal flood take the SPAN at the
height of whoever is asking — the same arithmetic with `spanIn` in front
of it. Standing in a hall you may walk out of the front door; standing
on the landing over it you may not, and it is the same line.

A HOUSE IS A FACADE
- - - - - - - - - -

The first cut of this town gave every house a hall, a stair, a kitchen
and two bedrooms behind every door, and a check that walked every one of
them from its own front hall. Nobody went in. A house at two in the
morning is a thing you look AT, and what those interiors cost — eleven
thousand regions of wallpaper — was spent where nobody was. So the
insides are gone, at the user's request, and the outsides got what they
cost.

THE SHELL of a house is one column of one storey: the roof, over the
whole footprint, shut everywhere below the eaves. THE WALL is a strip
twenty-four deep along each face, made of solid pieces — columns of the
same one storey — with RECESSES cut in it. A recess is a small open
sector sixteen deep with its floor at the sill and its ceiling at the
head, one storey per window in a column; eight units of void behind it
make its back wall a one-sided line, and a one-sided line wears its own
storey's texture, which is what lets one window column be lit upstairs
and dark down. The disagreement rule draws the rest without being told
anything: from the ground in front, the wall is a lower band from the
foundation to the eaves; where a recess is, the band stops at the sill,
starts again at the head, and between them is a hole with a sill, a
head, two jambs of brick and a pane at the back. A door is the same
hole with a door in it, painted, because there is nothing behind it.

THE FOUNDATION is a plinth: a strip eight deep at the foot of the wall
with its floor at thirty-two, so the bottom of the wall is a band of its
own and wears block — fieldstone for the church. At the door the plinth
is a stoop thirty-two deep, with a step half its height in front of that
and a path of flagstones out to the sidewalk. Two steps of sixteen up to
a door at thirty-two is a porch, and both are under the twenty-four the
engine lets you climb.

EVERYTHING THAT TOUCHES A GABLE WALL HAS ITS CEILING AT THE EAVES — the
plinth, the stoop, the gable strips — because above the eaves the ground
is shut and the roof storey is open, and that disagreement IS the gable.
A sky-ceilinged sector against the same wall would draw brick from the
ridge up to the sky. And the gable band FACES THE STREET: the
disagreement rule winds a wall to face its open side, and above the
plinth the open side is the attic. Nobody is in the attic. So an upper
band over a sector whose ceiling is the sky is wound the other way and
lit by the ground under the sky, or the house has a gable that can be
seen from inside its own roof and from nowhere else — which is what
every house had until somebody stood on the pavement and looked up.

THE ROOF YOU CAN SEE. Three things had to change before a roof was
anything but a black wedge on top of the wall, and the user drew a ring
round the wedge.

  THE PITCH. Every roof was 128 over a 384 half-span, one in three, and
    you are under the plane of a roof at one in three until you are
    twenty-one metres back from the wall: from the pavement in front of
    a house there was nothing above the eaves but sky, and from across
    the street a sliver. A terrace is six in twelve now, a house with
    its ridge along the street a little over, and a house with its
    gable to the street nine in twelve — 192, 208 and 168 of rise.
  THE EAVE. A roof with no edge is a plane you are under. So the ground
    under an eave wall is a COLUMN OF TWO: the plinth or the lawn or
    the stoop, with the soffit for a ceiling at the eaves, and over it
    the LIP — the roof's edge, eight of board thick, shingle on top and
    open to the sky up to the ridge. The disagreement rule draws it
    without being told: against the yard the lip is a band eight tall
    and wears FASCIA, a white line along the top of every wall; against
    the wall the same band is over the soffit where nobody sees it;
    between the lip and the roof both columns are open and nothing
    draws; above the ridge both are shut. It is thirty-two deep, the
    depth of the stoop, so the stoop is under it whole and a front door
    is under a porch. See underEaves in js/maps/town.js.
  THE GABLE TO THE STREET. Half the detached houses run their ridge
    back from the street instead of along it, so the front wall carries
    a triangle of board 448 wide and 168 tall over the door — the one
    shape that says HOUSE from the pavement. The other half show their
    eave to the street and their long slope from across it. Both are
    the town; a street of only one is a barracks.

And the shingle was the colour of tar, which was the palette and not the
light: the grey ramp's half-way stop is 92 of 255 with a gamma of 1.3,
so a shingle inked at what reads as a sensible four tenths came out at
fifty-eight against the ninety of the walls' bone at the same number,
and the daylight banding halved it again. The courses are inked in the
top half of the ramp now and the shadow lines under them carry the
contrast, and a roof at dawn is a grey surface with courses on it.

THE STREET, ROUNDED
- - - - - - - - - -

A KERB THAT GOES ROUND A CORNER, in a map made of rectangles. RectMap
has one new thing in it: a square may be an ARC. Give it `arc: {
centre, disc, rest }` and it becomes two sectors — the quarter circle
centred on the named corner, with the square's side for a radius, and
the curved triangle left over at the opposite corner. The two edges
that meet at the centre belong to the disc whole and the other two to
the rest whole, so every neighbour still sees a rectangle and splits
its own edges against it exactly as before; the arc is a matter between
the two sectors that share it, and they share every one of its vertices
by construction. A sidewalk's corner at a junction is a square of 96
with the disc pavement and the rest road. The outside of a bend in the
road is the whole middle of the junction, 320 square, with the disc
road and the rest pavement. See AN ARC in js/maps/rectmap.js.

THE STREETS STOP AT THE WOOD. A junction knows which of its four mouths
a street leaves by, and a mouth with none is pavement right across, so
the perimeter streets are a run of T's rather than roads that drive off
into the trees, and where two perimeter streets meet at the town's
south corners the road BENDS through ninety degrees on that arc. The
north edge opens onto the supermarket's lot, as it did.

THE SHOULDER. A carriageway is 76 | 84 | 84 | 76 on a residential
street: a parking lane, two travel lanes about the centre line, and a
parking lane, with the white edge line between each shoulder and its
lane. The bays are painted by the texture — ASPHPARK is one bay, 192
along the kerb, tiled from the world origin — and the vans are parked
at the same arithmetic, so they land between the lines: a slot in one
bay in sixteen goes onto level.carSlots and js/vehicles.js parks the
car park's van in it at load, in one of its five colours, in the one
slab of geometry the car park's own vans are already in. A hundred-odd
of them. A storm drain sits in the gutter near each end of every run
and every 1536 between, a grate 48 by 24 at road level against the
kerb. The sidewalk came down from 144 to 112 and the kerb from 24 to 12
to make the room, both at the user's request, and a kerb of twelve is
the plan's own number.

TWO THINGS IN THE ENGINE HAD TO GIVE, both found by standing in front of
a house and seeing no window in it. A band's two edges are the surfaces
lineBands cut it at, and the drawing has to ask THOSE surfaces at the
point: the first version worked the edges out again from the band's
kind, and a window under a sloped roof came out as brick from the sill
to the eaves, over every window in the town. And a hole between two roof
storeys is the same roof and nothing stands in it: the pane in a church
window was being hung there too, a sheet of coloured glass above the
eaves.

A terrace is one shell and one roof with sixteen front doors in it,
which is what a terrace is. On Main Street the ground floor is a
shopfront and there is no foundation: a shop stands on the pavement.

THE CHURCH AND THE SCHOOL KEEP THEIR INSIDES and get more of them. The
nave has pews down both sides of a centre aisle — a seat you can climb
on and a back you cannot — a wainscot that is a ledge eight deep and
forty tall along both long walls, which is the one way this engine puts
two textures on one wall, a raised chancel with an altar and a cross let
into the wall behind it, and twelve lancets of coloured glass, each a
recess on the outside and a recess on the inside with the pane hung on
the line between them, so you see in and out through it and stop at it.
The school has six classrooms with desks in rows and a blackboard let
into the west wall of each, lockers down the corridor you cannot walk
through, and steel windows you can see in through.

AND THERE ARE NO STAIRS ANY MORE, at the user's request. There were
three: the school's two, running along the corridor and open to it down
their length, and the church's switchback of two flights side by side
over the narthex. All three are gone and the floor each stood on is the
room it stood in. WHAT THAT COSTS IS WRITTEN DOWN RATHER THAN QUIETLY
LOST: the school's first floor and the choir loft are still built, still
lit and still furnished, and there is now no way to walk to any of them.
The fire's route changed with them — see A FIRE ON A GROUND FLOOR below
— and the reachability test asks for the ground floor whole instead of
asking for something nobody built.


A BUILDING IS WHAT IT DOES AT ITS EDGES
---------------------------------------

Both of them were, at the user's request, made immensely more detailed —
and what that turned out to mean was not more rooms. It was that a wall
which runs from the ground to the eaves with nothing on it is a slab,
and the town was full of slabs. Everything below is a BAND: a strip of
wall a few units tall that a piece of geometry standing proud of the
wall behind it makes the disagreement rule draw. One projecting
rectangle is one band; a rectangle with a gap in its column is two or
three. See THE TRIM in js/textures.js for the paint and the church and
the school in js/maps/town.js for where each one goes.

THE SCHOOL gets four things it did not have, and they are all the same
thing. A stone WATER TABLE it stands on. A STRING COURSE at first-floor
level. A CORNICE where the brick stops, so the building has a top
instead of just ending. And a PILASTER at every party wall between two
classrooms, every other bay of the gym and both corners — twenty-four of
them, which is what breaks two hundred and eighty feet of brick into
bays you can count. The first three come out of ONE rectangle: a strip
sixteen past the wall whose column is open, shut for sixteen, open,
shut for twenty-four, and shut, which is three bands for the price of
one and the reason the elevation is walked as segments.

AND THE FRONT DOOR IS A DOOR. It was a hole in a flat wall, and from
the lawn it read as a black wedge — which is the thing the user drew a
ring round. It is an ENTRANCE BAY now: two brick piers standing
forty-eight in front of the rest, a pair of steel doors between them
with the middle open and a leaf each side, a date stone over them with
no name on it ever, and the cornice carried round the front.

THE GYM was a black box a hundred and twenty feet long. It has a maple
floor with a court painted on it, padding round the foot of the walls,
three roof trusses across it, bleachers down the far side in three tiers
you can climb, and a stage at the east end. The stairs got a balustrade
on every tread but the one you got on by and the one you got off by,
and then the stairs were taken out altogether at the user's request —
see AND THERE ARE NO STAIRS ANY MORE above.

AND THEN THE SCHOOL WAS DONE AGAIN, at the user's request: taller
ceilings, thinner lockers, better desks, more in the gym, an auditorium,
and detail everywhere else. Six things, and the first of them paid for
half of the rest.

A SCHOOL IS NOT A HOUSE AND ITS STOREY IS NOT A HOUSE'S. The town's
STOREY is 96 of clear over 16 of deck, which is a living room, and every
room in the school was built against it — so the corridor had the ceiling
of a hallway and the gym, which is two of them stacked, was 224. It has
its own now: 128 of clear and 144 to the floor above, and the gym is 288.

What made that a small change rather than a large one is that the
building is written against B.eaves and two numbers. Hand `building()`
the eaves it should have and every column, every window band, every
course of trim and the roof over all of it follows. The windows grew with
the rooms: 64 tall in a 96 room is a window, and in a 128 room it is a
porthole, so they are 112 now — most of the wall between the sill and the
ceiling, which is what a school window is. And every classroom got four
light fittings instead of one, because light falls off with distance and
the ceiling had just moved thirty-two units further from the floor.

A LOCKER IS TWELVE INCHES BY SIXTY. One repeat of LOCKERS is two of
them, and nothing had ever declared a size — so the repeat was 64 by 64
and a locker came out 32 wide and 64 tall. One to two is a kitchen
cupboard. Declared at 24 to the repeat, a door is twelve by sixty-four,
which is one to five, and a bank of them down a corridor is a bank of
them rather than a row of doors. The picture is still painted 64 across
and is therefore SQUEEZED nearly three to one on the wall, which is why
everything in it that has to read is horizontal: the vents, the number
plate, the seams. Anything drawn as a narrow upright would not have
survived.

A DESK IS A DESK AND A CHAIR. It was one raised block 32 by 24 wearing a
laminate top, which from the door is a run of lab benches. It is three
raised floors in a row now — the top you write on at 30, the seat behind
it at 18, the back of the chair at 42 — and the silhouette is the whole
of it. There is a teacher's desk in the corner by the board as well,
turned to the room, which is where the one in every classroom in America
is.

AND THEY ARE TURNED THE RIGHT WAY, which they were not. The blackboard
is let into the WEST wall of each room, so a child at a desk looks west;
the old layout put four desks across the room in three rows down it,
which faces them ALONG the board rather than at it. They are in ranks
running back from the board and files running across it now, and the
chair of every one of them is on the east side of its own top. The suite
holds exactly that: every chair stands east of its own desk.

THE GYM GETS WHAT A GYM HAS. A backboard at each end of the court with
the ring and the net painted on it, braced back to the wall; a scoreboard
with HOME and GUEST and four amber digits; Swedish wall bars; and the
only three good years the school ever had, hanging off the trusses as
pennants. None of it is in anybody's way — the boards and the pennants
are at twice head height, and the bars and the scoreboard stand on the
PADDING, which is a raised floor 32 above a MAX_STEP of 24 and therefore
a place nobody can be.

AND THERE IS AN AUDITORIUM, which is a WING and not a room.

The plan was full: a corridor with six classrooms and an office hung off
it, and twelve hundred units of gym at the east end. There is nowhere
inside the box to put a hall you can seat four hundred in, and the only
place a school of this age ever puts one is out the back. So it is a
thousand by six hundred and sixty-four standing out of the back of the
gym, with its own shell, its own roof, its own doors off the yard, and
the back yard cut into four pieces round it.

WHAT AN AUDITORIUM IS, in this engine, is a RAKE. The floor steps DOWN
from the doors at the back to the orchestra at the front — five banks,
twelve units apart, which is half a stride, so you walk down it without
noticing you are walking down it. Every bank is a carpeted tread with a
raised strip of seats standing on it, split by a centre aisle and two
side aisles, which is the plan of every hall of this kind ever drawn.

At the bottom is the stage, raised forty-eight and boarded, with a
curtain leg standing floor to ceiling each side of the opening. And over
it the PROSCENIUM, which is the one thing in this whole map that is an
UPPER band: everything else here hangs off a floor, and a proscenium
hangs off the ceiling — so it is a region with a low ceiling, and the
band above it is drawn by the disagreement rule out of that storey's
upperTex.

The outside of it was a brick box, which is the same hundred feet of
unbroken wall the terraces had, and it gets the same three answers:
something upright every so often, something horizontal at the floor line,
something at the top where the wall stops. Here they are free boxes
rather than rectangles of ground — a pilaster every 160 down both long
sides, a string course, a cornice, and the louvres a hall with four
hundred people in it and no windows has to breathe through. Ten proud
and no more, which is the rule every box at head height in this town
keeps.

AND WHAT A SCHOOL HAS ON ITS WALLS: the case by the door with everything
it has ever won in it, cork boards with notices nobody has read, two
drinking fountains, a radiator under every classroom window, and a clock
over every door so the hour is the same everywhere, which in a school it
never is. Every one of them is flat against something you could not have
walked through anyway and under ten units proud of it.

Sixteen new textures for all of it, and two repaints. LOCKERS is above.
DESKTOP was a blank sheet of laminate with one line on it, which at the
size a desk is actually drawn is a blank sheet; it has the pencil groove
now, the pencil in it, the hardwood lip, the ring off a bottle and
everything that has ever been done to a school desk with a compass point.

THE CHURCH gets the same treatment and one thing the school cannot have.
A water table, a BUTTRESS in the middle of every gap between two
lancets and one on each back corner — two stages, sixteen proud to the
set-off and eight proud from there to the eaves, because a buttress is
a wall that gets thinner as it goes up and sheds the rain at every
change. EAVES down both long walls, which it had none of: the roof met
the wall with no edge at all and the whole thing read as a shed. A
tower in stages with LOUVRED BELFRY openings on three faces and a
cornice the spire springs off rather than grows out of.

AND THE NAVE IS OPEN TO THE ROOF, which is the one thing here that is
not a band. The roof storey has always been an attic — floor NONE,
ceiling NONE, nobody in it — and a church is the one building where
that is false. Name a SOFFIT and the roof storey gets a ceiling: the
boarding and rafters you are looking at from a pew, whose other face is
the shingle on the street, drawn from the same triangles wound the other
way. The nave's own ceilings then say NONE and you are looking straight
up into it. Tie beams cross it at two places, the chancel arch is five
rectangles and two piers, and there is a communion rail with a gate, a
pulpit, a lectern, an organ on the choir loft and a rail along its edge.

WHICH NEEDED ONE ENGINE FIX. A gable is wound to face the street,
because the other side of it is an attic and nobody is in an attic. With
the nave open to the rafters that stopped being true, and the far end of
the roof was a triangle of sky — the gable drawn once, facing away from
the only person who could see it. It is drawn the other way as well now
when the roof space is one with a ceiling, and lit by that ceiling. It
costs the houses nothing: their attics say NONE and never ask.

AND THERE ARE FENCES, at the user's request. Chain link round the ball
field, wrought iron along the churchyard with the gate where the path
is, chain link along the school's frontage, and PICKET down every lot
boundary in the town. A fence is not a sector: it is a masked texture
hung in the hole between two patches of ground that are both open to
the sky, which is the same thing the mall's service yard has had since
there was a mall, and it is why a fence is something you see the ball
field THROUGH.

AN AMERICAN FRONT YARD IS OPEN AND A BACK YARD IS NOT, and that one
fact is most of what a street of houses looks like from the pavement:
lawn running unbroken from door to door along the front, and behind
every house a square of ground with a line round it. The town had
neither and the whole depth of a block read as one field with houses
standing in it. So the picket runs from the FRONT CORNER of the house
back, never across the front yard, and along the middle of the block
where the two rows meet back to back.

IT IS FOUND AND NOT PLUMBED. The ground either side of a lot boundary
is half a dozen rects laid by two different houses that never heard of
each other, so rather than thread a rect back out of house(), the
boundary is asked for what has an edge on it, and a fence takes a LIST.
The lines that do not exist between two rects that never touch cost
nothing, and a house that changes the shape of its yard tomorrow needs
no change at the block.

AND THE WIRE ITSELF HAD TO BE REDRAWN, at the user's request. The chain
link was crossed diagonals with a line top and bottom, which is a
screen door: a crosshatch has no depth and the eye knows it. Real chain
link is WOVEN — at every crossing one strand passes in front of the
other, alternating, and that single-pixel break in the one going under
is the whole of what makes it look woven rather than printed. Round
galvanised wire lit from the top left, a top RAIL (the one solid part
of a chain link fence, and what stops the whole thing reading as a net
hung off nothing), knuckled selvage under it, a post and tension bar at
the end of the bay, and a tension wire along the bottom. One repeat is
one BAY, so the post lands where a post goes. The picket is the same
bargain: pointed boards with air between them, two rails behind and
therefore darker, a post with a cap, and the bottom four units gone
green where the mower never reaches.

A BOX THAT BELONGS TO NO SECTOR, at the user's request, who asked for
massively more structure on every building in the town. A sector engine
can do a great many things and there are three it cannot do at all: it
cannot put anything ABOVE a roof, it cannot put anything in FRONT of a
wall without carving the ground in front of that wall into pieces, and
it cannot have two things at the same x,y unless one is over the other
in the same column. Which rules out, in the order a town misses them:
the chimney, the porch, the cornice, the dormer, the downpipe.

A ROOF ALREADY HAD THIS PROBLEM and already had the answer — level.roofs
is a list of footprints drawn as free triangles and owned by no region,
which is how a sector engine gets a sloped roof at all. boxGeometry in
js/mapgeo.js is the same bargain for a box: six faces at a place,
batched into the block it stands in, rebuilt when that block is, lit by
a number the map hands over. THE WINDING is the whole of the work, and
it falls out of the rule the rest of that file already follows: the
map's y is the renderer's minus z, so walk the four sides
counter-clockwise on the PLAN and wind each one the way addQuad winds a
line's front, and every face looks out; the lid is the ring itself, in
plan order, which is what a floor is.

WHAT IT COSTS is what a roof costs. A box is not a region, so it is not
in the portal flood, it holds no fuel, nothing walks on it and nothing
collides with it. So the rule that keeps it honest is that every box is
either ABOVE HEAD HEIGHT or flat against a wall you could not have
walked through anyway, and the suite holds that: nothing but a post, a
pipe, a corner board, a pilaster, a cabinet and a ladder comes down to
head height, and every one of those is under ten units thick.

THERE IS NOW ONE EXCEPTION AND IT IS DELIBERATE: the car park's precast
wheel stops are boxes standing on the ground, twelve tall against a
MAX_STEP of twenty-four. Walking through one and stepping over one are
the same move, so there is nothing to notice, and the suite holds them
to that number rather than to the rule. Two hundred and sixteen of them.
Everything the size of a skip went back to being a REGION.

AND NO TWO OF THEM MAY SHARE A FACE, which the user found by seeing it
shimmer at the checkout.

Z-fighting is two coplanar quads facing the same way. Every face of a
box winds outward, so two boxes that merely INTERSECT are fine — a
chimney driven through a coping has no two faces in one plane — and two
that merely TOUCH are fine as well, because the plane they share carries
one quad facing each way and whichever you could see is the far side of
solid geometry. What is not fine is two boxes sharing a face plane AND a
volume: both have a front-facing quad there, at the same depth, and the
depth buffer has no answer. What you get is a seam that crawls as you
move.

Four places had it and every one was the same mistake — a piece of trim
run the full length and another run the full width, meeting at a corner
they both wanted:

  the belt guards            against the end plate and the roller cover
  the shopfront mullions     against the cill they stand on
  a door frame's jambs       against the head that sits on them
  and two wall packs         both wanting the mullion between the doors

All four are fixed the way a joiner would: the guards run BETWEEN the
plates, the mullion starts at the top of the cill, the head sits ON the
jambs, and there is one pack on the mullion instead of two.

IT IS ONLY A BUG WHERE YOU CAN SEE IT, and that is not pedantry. Every
cornice and every window head in the town starts two units inside the
wall, so all of them share that plane with each other — two hundred and
thirty-nine pairs, every one back-facing and culled, and a check that
counted those would be a check nobody could keep green. So the suite
steps off along the face's own outward normal and asks whether a player
can stand there, by the same flood and the same standing floor the
head-height rule uses. A hundred and fifty-eight pairs failed that test
before this pass and none do now.


AND A BOX CAN HAVE AN UNDERSIDE, which it could not at first. Six faces
was really five: a box has no bottom, so from below every side is wound
away from you and there is nothing there at all — the thing goes
transparent the moment you walk under it. Fine for a chimney. Wrong for
the three things in this game you stand directly beneath, which are a
porch roof, a shop awning and the canopy over a fire exit. `botTex`
draws the lid's two triangles wound the other way and darker, because
the underside of a slab in daylight is the one surface on it that never
sees the sky.

WHAT WENT IN, and why each of them and not something else:

  THE CHIMNEY, which is most of what a house is from three streets
  away. Brick from under the eaves — so the roof closes round it and
  there is never a gap between the brick and the shingle — up to
  forty-four over the ridge, with a cap that OVERSAILS by six. That six
  is the whole reason a chimney reads as masonry rather than as a
  brick-coloured post: it puts a hard shadow all the way round.
  THE PORCH: a roof on two posts over the front door. A door with two
  steps up to it and nothing over it is a fire exit.
  THE CORNICE, on every terrace. A wall that stops dead at the roof
  reads as a cut-out; a wall that stops at a moulding standing fourteen
  units out of it reads as a building, because the moulding puts a line
  of shadow under itself the whole length of the street. With a string
  course at the first floor, where the joists really do land.
  THE AWNINGS over Main Street's shopfronts — striped canvas, over the
  window and not over the door, and three in ten have taken theirs in.
  THE DORMERS, on half the houses whose slope faces the street and
  every third house of a terrace, because a roof is the one surface on
  a building bigger than the gable.
  THE GABLE VENT, which is the one piece of ornament on a house that is
  not ornament at all: an attic has to breathe. A gable with nothing in
  it is the largest blank surface on an American house.
  THE WINDOW HEADS: a hole in a wall with nothing over it is a hole; a
  hole with a board standing six units out over it is a WINDOW, and the
  difference is one line of shadow.
  THE CORNER BOARDS and THE DOWNPIPES, which are the two things that
  give a flat wall a vertical.

TWO THOUSAND SIX HUNDRED BOXES IN THE TOWN, and they cost sixty-five
draw calls on a town street — 548 before, 613 after — because the cost
of a box is not the box, it is the texture: a block pays one draw call
per texture in it, and these brought eleven new ones. The block LOD
drops them at distance with everything else, which is why the number is
sixty-five and not six hundred.

AND ABOUT FOUR HUNDRED AND SIXTY MORE OUT ON THE PARADE afterwards —
the coping, the pilasters, the pier caps, the downpipes, the gutter, the
fascia trays, the roller housings, the wall packs, the rooftop plant and
the wheel stops, for which see WHAT A STRIP MALL HAS THAT A SHED DOES
NOT. Fifteen new textures, and the same shape of bill: forty-three draw
calls in the middle of the car park (208 to 251), twenty-four on the
footway (270 to 294). Neither costs a frame; both are measured rather
than assumed.

WHICH ALSO SETTLED WHERE MASKED BELONGS. Three of the new textures went
in masked — a truss, a handrail, a communion rail — and what you saw
through all three of them was the SKY. A masked texture only works
where there is something behind it, and a BAND has nothing behind it by
construction: a band is the one quad drawn where two columns differ,
and the differing is exactly the part of the world with no geometry in
it. Masked belongs on a MIDDLE texture, in the hole between two open
sectors. Everything that is a band paints its own dark.

THE STREET has lamps — one every 1536 along each sidewalk, staggered so
the sides alternate, and one on every corner — each a photographed road
light stood flat across the street, over a pool of light that is a
brighter sector of pavement, which is the only way this renderer casts
light. The yards have trees, the foundations have shrubs, the parks have
flagstone paths across them and the cemetery has its stones, and all of
it but the lamps is sprites, placed by the town and grown by
js/forest.js, which is why a yard has no rectangle for any of it.

THE STREET LAMP IS A PHOTOGRAPH, AND IT IS NOT A SPRITE. It was a sprite:
an acorn globe on a post, twelve by sixty-four, drawn by js/sprites.js and
stood at twice the size, fullbright. The user sent a photograph of a real
one — a cobra-head road light on a tapered aluminium pole — and a
photograph of a lamp post cannot be a sprite, for a reason that took a
minute to see. A sprite turns to face the camera plane. This picture is a
pole with a bracket arm reaching out on ONE SIDE of it, so as a sprite the
arm would swing round to point at you wherever you stood, and a street of
them would be a street of lamps all pointing at the player. Doom never
had the problem, because Doom's lamps were symmetrical.

So it is a FLAT CUT-OUT, stood in the world at a fixed angle: two masked
quads in the vertical plane ACROSS the street, the foot of the picture on
the thing's own x,y and the arm reaching the way the thing's angle says,
which the town sets toward the road — over the parking lane on a straight,
into the junction on a corner, across the path in a park. Walk down a
street and every lamp on it shows you its profile with its head out over
the carriageway. Stand under one and look straight across the road and it
is edge-on, a line, and then nothing: that is what a flat cut-out is, it
is what the user asked for over a billboard, and it is also what a lamp
post is edge-on. Both faces are drawn, and unlike a fence — whose two
faces each read left to right from their own side — both put the SAME
texel at the same point in the world, so the arm reaches over the road
from whichever side you see it; from behind, the picture is its own mirror
image, and a lamp post is not chiral. It goes in the block's SHELL with
the roofs, because a lamp is what you read a street by from the far end of
it. See THE STREET LAMP IS GEOMETRY in js/mapgeo.js. The actor is still
there for its radius, with no sprite, the way the LAMP fitting is there
for relight().

TWO TILES, CUT WHERE THE THING IS. The photograph is 172 by 493 and the
64-pixel rule holds for it as for everything: one tile for the lot at 64
tall gives the pole a single texel, and a grid of eight, the way the logo
is four, spends six of them on the air either side of the pole and costs a
draw call each. So the HEAD — the arm and the luminaire, across the whole
width and the top eighth of the height — is a 64-wide tile at its own
aspect, and the POST — the pole and its base plate, a quarter of the width
and all the rest — is a strip of 24 by 64, and SIZES declares each at the
lamp's own size, 256 tall, which is a road light and not a Main Street
post. Where the head stops and the post begins is MEASURED off the
photograph by the bakery, not typed: the first row under the arm where
nothing but the pole is solid. So are the foot (the pole's mean column, as
a fraction of the width — not the middle, the arm is all on one side) and
the lens (the underside of the luminaire), and they travel in art-data.js
as fractions so that nothing downstream knows how big the photograph was.

AND THE WATERMARK. The file carried a sparkle in its bottom right corner,
twenty pixels across, in a pale magenta that the chroma key test happens
to catch; "happens to" is not a guarantee anybody should ship a picture
on. So a cut-out now keeps only its LARGEST CONNECTED PIECE — the lamp is
one piece, pole to luminaire by way of the arm, and anything not touching
it is a watermark, a sparkle or somebody's corner logo and goes. It runs
on every cut-out in the bakery, changed none of the stones or the iron by
a byte, and prints what it dropped.

THE LAMP IS ALSO ON, after dark, and that is two things, neither of them
the lamp. A photograph of a lamp is a lamp that is off; what a lamp IS at
night, from across a street, is a point of cold light with a line across
it and the pavement under it going pale.

  THE PAVEMENT is the map's. The pool under a lamp was already a brighter
  sector of pavement, which is the only way this renderer casts light; but
  a sector's light is a NUMBER, and a mercury-vapour lamp's light is not
  the sky's colour — it is the cold white with green in it that every
  American street was lit by from the fifties until the sodium came. So a
  surface the map marks as lamp-lit (one float per vertex, `lamp`, on the
  pool and on the lamp's own post) has its albedo tinted by LAMP_LIGHT,
  only after dark — lampsOn is a smoothstep on the sky's light, on as it
  goes under a half and full by a fifth, so by day the sky lifts the
  pavement to full and the lamp is off — and ahead of the banding, so it
  steps with everything else. One attribute and one multiply, and the
  tint and the flare are the same constant in js/material.js, or the pool
  on the ground would be a different lamp from the one over it.

  THE POINT AND THE LINE are js/lamplight.js: one ANAMORPHIC FLARE per
  lamp, the gunship's searchlight shader in miniature — a horizontal
  streak, bluer than the light because it is the lens's colour and not the
  lamp's, with a bloom at the centre that goes to white at the heart — and
  SUBTLE, at the user's request: a fifth of the frame across where the
  gunship's is most of it, and fading with the distance and a half to
  nothing at 2400, its size pulled in with it, so a lamp at the end of the
  street is a point with a hair across it and the one over your head is a
  lamp. The gunship has one lamp and one mesh with a uniform for where it
  is; the town has four hundred and four, and four hundred meshes with
  four hundred uniform updates a frame is the crowd's problem again. So
  the flares are ONE BUFFER of forty quads with the centre of each in an
  ATTRIBUTE, and every frame the nearest lamps that could be seen at all —
  within range, not well behind the eye, in a region the portal flood can
  see into — are dealt into the slots. It is one draw call whether that
  is three lamps or forty. Then the test that costs something: a SIGHT
  LINE from the eye to the lens, the same call a trooper uses to decide
  whether it can see you, so a lamp behind a house does not flare through
  the house — asked of a third of the slots a frame and eased onto over a
  sixth of a second, for the reason the gunship's is: a flare that pops off
  at a wall edge reads as the flare being broken.

What it costs: two draw calls per block that has a lamp in it, one for
all the flares, and about thirteen sight lines a frame. What it does not
do: the head is sector-lit and dark at night behind its own bloom, the
post is lit by the pool it stands in and not by itself, and nothing casts
a shadow, because nothing in this game does.

AND THE VERGE HAS TREES, which is what the verge is for. The strip
between the sidewalk and the kerb is sixteen units wide and was laid in
the first cut of the streets because an American street has one; what it
did not have was the thing it is named after. It has six now — six
photographed broadleaves, one every 512 with the pitch offset by a third
between the two sides of a street so the rows do not line up, skipping
any that would stand in a lamp's pool. A street of the WOOD'S trees is a
town in a national park; six hundred limes down the verges is the single
change that made the grid read as a place somebody lives.

THE TOWN IS ALSO HEDGED, in clipped box, and the hedge is a BOX — at
the user's request, and it was a row of sprites. One photographed block
of box per 64-unit cell of the wood's grid, each of them swivelling to
face you. What is wrong with that is not the picture, it is that a row
of pictures that all turn to face you has NO CORNER: no end you can
walk round, no thickness, no top going away from you, and the whole run
turns as you walk past it.

SO IT IS A SECTOR WHOSE FLOOR IS THE TOP OF THE HEDGE. The band down
its side is the hedge (HEDGESID, one repeat for the whole height, dark
at the roots and clipped bright along the top), the floor you see over
it is the clipped surface (HEDGETOP), and forty units of step is nine
more than the engine will climb, so it stops you the way a hedge does.
Forty and not the seventy-two the sprite stood at, because forty is
BELOW THE EYE at forty-nine and the whole point of a green is that you
can see across it.

AND THE GROUND HAD TO BE LAID ROUND IT. Two rects may not overlap, and
every hedge in this town runs through the middle of a lawn somebody
already laid — so a run is recorded as it is asked for and cut in at
the end, in carveHedges: the lawn it landed in is split into the four
rects round the hole, the original rect object staying as the biggest
of them so that anything already holding it still holds something real.
Where two runs meet, the second is shortened off the end that is
already box. The pieces are a FAMILY and the one thing that cares is
the wire, which now hangs between every piece of one and every piece of
the other. Forty-four runs of it edge the green, return at every gate,
run along the school's foundation and stand inside the churchyard's
iron; none of them landed on nothing, and the suite holds that at nought.

THE CEMETERY IS THE ONE THAT NEEDED ALL OF IT AT ONCE. The block is laid
as a ring of verge, four gates and the ground inside, because a fence in
this engine is a masked MIDDLE texture hung in the line between two
sectors that are both open to the sky — a fence on the block's own edge
would have nothing behind it. Eight runs of wrought iron go in the eight
lines between the ring and the quarters, stopping either side of each
gate. Inside, eight kinds of headstone are dealt so the plain slabs are
common and the obelisk and the two crosses are not, and they are laid in
RANKS: the jitter is along the row and in the angle and never across it,
because the line is the whole difference between a cemetery and a field
with rubble in it. The ranks step round three specimen trees a quarter,
the way a graveyard's rows step round the yew that was there first.

AND THE ROOF IS A STOREY. It was geometry first — two slopes and two
gable triangles over a footprint, pushed into a batch, with nothing in
the engine knowing it was there. You could walk through one. You could
shoot through one. It was a picture of a roof.

So a sector's floor or ceiling may be a HEIGHT OVER THE SECTOR rather
than a number, in two kinds and no more: a PLANE, and a GABLE, which is
two planes meeting at a ridge and is the one shape a plane cannot do.
Every rect of a building gets one more sector on top of its column
whose ceiling is the building's gable, shared by every rect so that a
terrace is one roof and not sixteen — and for a house that one sector is
the whole column.

`floor` and `ceil` survive as the numbers they always were, and they are
the SAFE end of the slope: a sloped floor's `floor` is its lowest point
and a sloped ceiling's `ceil` is its highest. Everything written before
there were slopes reads those and gets the answer that never claims more
room than there is — which is what a fire grid, a light and a sound all
want. The code that has to be exact asks floorAt and ceilAt, and that is
collision, sight, hitscan, and where your head is.

TWO THINGS IN THE DRAWING HAD TO GIVE. A flat is triangulated with its
corners at their own heights, and a triangle that straddles the ridge is
cut in two first, because three corners on a roof do not put the middle
of the triangle on it. And a wall under a gable is a TRIANGLE and not a
trapezium — the end wall of a house goes from eaves up over the ridge
and down to the other eaves — so the line is cut where the ridge crosses
it and each piece is a quad again. At most one cut per slope and none at
all for every wall in the supermarket.

There is precedent for geometry-over-a-footprint and it is still there:
`roofFraming` hangs steel over a burnt-out region without any sector
knowing, and the church spire is still drawn — a pyramid is four planes
and a gable is two. The school and the church wear built roofs now.

THE WEIRD PLUS-SHAPED GLITCHY WALL THING
----------------------------------------

The user sent four photographs of a brick cross eight storeys high
standing in an empty car park at the east end of the town, and asked
what it was and for an office building to be put there instead.

WHAT IT WAS. Block A5 was the services block, and what was on it was
three rectangles of asphalt: a station lot, a "fire station apron" and a
"police lot". No building on any of them, and between each pair the
map's usual sixteen units of VOID, because in this map the wall between
two rooms is the rectangle nobody laid.

INSIDE A BUILDING THAT IS A WALL AND IS WHAT IT IS FOR. Out in the open
it is a free-standing slab. A line with a sector on one side and nothing
on the other is ONE-SIDED, and a one-sided line draws its wallTex over
the whole height of the sector it has — so the sixteen-unit slot along
the station lot's north edge, with the lot open to the sky at 768, came
out as a wall of BRICKRED three thousand and seventy-two long and seven
hundred and sixty-eight tall. The slot between the apron and the police
lot crossed it at right angles. From the road, at night: a brick cross
eight storeys high standing in an empty car park with nothing under it.

THE OBVIOUS SUSPECT WAS INNOCENT, which is worth writing down because it
took a while. The two lots were also laid with `ceil: 2 * STOREY` — a
ceiling at 224 in a block open at 768 — and that looks exactly like the
disagreement rule hanging a five-hundred-and-forty-four-unit band over
them. It is not: a step between two patches of SKY draws nothing, and
the rule that says so has been at the top of the band loop in
js/mapgeo.js since there were bands. The lid was invisible. It was the
void that showed.

Which leaves a rule worth having. A void is a wall, and a wall wants
something on the other side of it — a room, a shop, an attic, anything
with a roof on. Leave one standing in open ground and it is a slab of
brick in a field, and the map file cannot tell you, because from the
inside a void looks the same either way.

So the suite has the general case. Every one-sided line in the town
whose sector is outdoors and at grade and more than a hundred and sixty
tall is collected, and there had better be none of them. It was run
against the old geometry before it was written down: rebuilt from those
three rectangles alone it finds twelve, the tallest 768 tall and 3072
long. Against the town as it stands it finds none.

AND THEN THE OFFICE BLOCK, at the user's request: a building, an
accessible ground floor, intricate detail, and a parking lot out front.

A speculative suburban office block is a building in a car park, and the
car park is bigger than the building. The lot is the supermarket's in
miniature and built out of the same pieces — four rows of bays back to
back facing each other, three driving lanes, a kerbed island of grass
and trees along the front, a column of lot lighting every four bays on
the line where two rows meet nose to nose, wheel stops on the two rows
nearest the doors, a drive cut through the verge, and eighteen
cars in sixty bays, parked fuller at the front than at the road, which
is what a lot looks like when a building is half let. Behind the building is a service yard with painted
bays, a hatched fire lane, a skip and the two points the fire brigade
and the police still come from — `arrivalPoints` has read `town.stations`
since there was a town, and what it reads now is a yard behind a
building rather than a lot with a ceiling over it.

FOUR STOREYS AND A FLAT ROOF, which is the first one in the town. A flat
roof is a SLOPE OF NONE — the case topOf() has handled since the church
tower put a spire over a shut cap — but the cap here is not shut: it is
an open storey forty units tall inside the parapet with ballast for a
floor and the sky for a ceiling, so that the packaged units standing on
it are standing on something and so that a building 584 tall has a top
when you are above it. It is the second thing in the game to break the
mall's 480, after the church spire, and the only square-topped one.

ITS ELEVATION IS THREE BANDS out of one strip, which is the school's
trick with a different accent. A strip of outdoor air sixteen in front
of the wall whose SHUT GAPS are the courses: a base course of polished
granite at the pavement, a cornice twenty-four under the roof line, and
the PARAPET — and the parapet is the new one, because it is the only
band in this map drawn ABOVE a roof rather than under one. Every other
band in the town hangs off a floor below the eaves; this one is a
degenerate storey at 584, forty over the roof deck, and the wall from
the deck to the coping is the gap under it.

Between the courses, a pier at every line where a wall inside the
building reaches the outside of it, wearing ribbed aluminium. It is the
one thing this building tells you about its own plan.

AND THE RIBBON. Twenty-nine bays of glazing, a hundred and twenty-eight
wide and seventy-two tall, four floors in every one of them, each lit or
dark on its own — a recess sixteen deep on the outside and one eight
deep inside it touching the room, with the pane hung on the line
between, which is the school's window with four storeys in one column
instead of two. A block of offices at four in the morning is read
entirely off which of those are lit, and it is the only thing that makes
one look occupied.

THE WAY IN taught two things, both of them in one screenshot.

The first: the entrance is a bay standing fifty-six in front of the wall
with the glazing recessed between two piers, and either side of the
doors is a SIDELIGHT. The first cut made a sidelight what a window is —
an open storey on each of the four floors — and what you got from the
forecourt was a slot straight through the lobby and out of the lit
offices on the far side of the building, four storeys of it, either side
of the door. A sidelight is a SHUT STOREY, the same as the leaves beside
it: glass from the floor to the head and the wall over it.

The second: the recess itself was open from the sign band to the
cornice, fifty-six deep and three hundred and thirty tall, and the
sidelight beside it is shut over that whole range with nothing to hang a
texture on — so lineBands fell through to the roof storey's upperTex,
which is NONE, and put a HOLE in the front of the building. Above the
canopy the entrance is shut now, and every storey over it is a
degenerate one whose only job is to say what the band under it wears:
the sign, the wall, the cornice, the parapet.

And a third thing, which is not an engine lesson, only a good one: there
was a downpipe standing in the middle of the front door. Free boxes went
down the middle of each face at u 1160, and 1160 on the front elevation
is eight units off the centre line of the doorway.

THE GROUND FLOOR, AND YOU CAN WALK INTO IT. Off the plaza, up a step,
under the canopy, through the doors: a lobby in terrazzo with a
reception desk, a seat, a directory by the door, a clock and two ficus
in planters that have been there since the building opened. Across the
corridor, the lift lobby with two lifts that do not go anywhere, because
the stairs came out of this town at the user's request and nothing was
ever going to take you up. Behind them the restrooms. West down the
corridor: a break room with a counter, a coffee maker, two machines,
three tables and a cooler; a copy and mail room with the copier, a work
table, the filing and the door to the yard. East: a conference room with
a table, six chairs and last week's meeting still on the whiteboard, and
four private offices that are the same office four times, which is what
they are in life.

And two open-plan floors of CUBICLES, which is the object that says
office more than any other. A POD is two rows of them back to back:
chair, work surface, spine of partition, work surface, chair — a hundred
and twelve deep, and the unit every open-plan floor in the country is
laid out in. The partition is a raised floor at FORTY-FOUR, which is
over the desk and under the eye at forty-nine, so you see across the
room and not into the next cubicle; that is the whole design intent of
the object and the reason it is that height in life. It is also twenty
over MAX_STEP, so it stops you the way a hedge does.

The three floors over you are built, lit and glazed and there is no way
to reach any of them. Written down rather than quietly lost, the way the
stairs were.

TWENTY-SIX NEW TEXTURES for all of it: the precast panel with its
sealant joints, the granite base, the parapet with its coping, the
ribbed pier, the ribbon lit and dark, the entrance leaf, the number over
the door, the ballasted roof, terrazzo, carpet tile, the reception desk
and its stone top, the lift doors, the cubicle panel and the desk you
look down on, a filing cabinet, the board table, the whiteboard, a
vending machine, the break-room counter and its top, the water cooler,
the lobby directory, the copier and the ficus. All at 64 pixels or
under, as everything in this game is.

AND THE PEOPLE ON THE STREET
----------------------------

At the user's request, and the town had nobody in it: twenty-five
blocks, a school, a church, a green, a cemetery, seven hundred and
thirty-six people inside the supermarket and not one person outside it,
which at two in the morning reads as exactly what it is. There are five
hundred and sixty out there now.

WHERE THEY GO IS NOT A LIST. Writing coordinates for five hundred people
is five hundred chances to put somebody inside a hedge, and every one of
them goes stale the moment a block is re-laid. So the town is ASKED
instead. Every rectangle already in the RectMap that is outdoors, at
grade, inside the town's own grid and wearing a surface a person would
stand on is a candidate, weighted by what it is: a sidewalk is where
people are, a pool of lamplight is where they stop, a path and a
crossing are where they are going, a lawn is where a few of them are, a
parking lot is where two or three are, and a CARRIAGEWAY is not on the
list at all, which is the whole of why nobody is standing in the road.
Move a block and the crowd moves with it, because the crowd is a fact
about the rectangles and not a fact about the town.

The weights had to be looked at once. Concrete started at the sidewalk's
and the gas station's forecourt is one rectangle of it three thousand
units square — a tenth of the whole town standing about on the same
empty slab. It is worth a fifth of a sidewalk now.

THE SPACING IS THE OTHER HALF, and it is the shop's lesson at town
scale: people dropped at random into a big enough space land apart, and
dropped into a small one land on top of each other. Ninety-six is about
ten feet — close enough to read as a street with people on it, far
enough that everybody has a step they can take when the fire arrives.
And nobody is standing inside a parked car: the vehicles are models
rather than sectors and nothing else in the level would have noticed.

THEY ARE NOT SHOPPERS, and that is the whole reason the type exists.
Three things in this game mean "the crowd in the supermarket" when they
say shopper: `peopleLeft`, which is the number over the HUD and is how
much of the STORE is still alive; the crowd LOD, which draws a fraction
of them by id; and the suite, which holds every one of them against the
sales floor rectangle. Five hundred and sixty more SHOPPERs would have
made the first two wrong quietly and the third fail loudly. A TOWNIE
inherits everything else — it burns, panics, freezes, gibs and drags a
trail of fire down a sidewalk exactly as the crowd in the aisles does,
because all of that belongs to a person near a fire and not to a person
near a shelf. The two numbers that differ are how far a fright carries
and how long it lasts: a street is not an aisle, you can see further
down one, and there is somewhere to run to.


FIRE THAT CLIMBS
- - - - - - - - -

The fuel grid has a plane per storey now. Plane 0 is the ground
everywhere and is exactly the grid it always was, which is why nothing
that indexes it by cy*cols+cx knows the rest is there.

A fire on a ground floor finds the stair, where there is one. A stair
open to the corridor down its length puts the top tread's air into the
corridor above, and fire goes up that FOUR TIMES as readily as it goes
along, because a staircase is a chimney with a handrail. The ceiling is
the slow way, a tenth of that, straight up and same cell. Both were
needed: with only the stairs, one cell of one tread has to win a race
against its own fuel running out, and it loses, and a building burns to
the ceiling and stops.

THE TOWN HAS NO STAIRS IN IT NOW, so what is left is the slow way, and
the second path turns out to carry the building on its own: poured over
the school's whole ground floor the fire still reaches the corridor
above and two classrooms off it. Fewer regions than it took with the
stairs, which is what a ceiling instead of a chimney should look like.
The engine keeps both paths; the map has stopped using one of them.

AND THE FUEL IS THREE HUNDRED AND OVER in both buildings, because the
spread chance in js/fire.js climbs as the 2.4th power of the fuel up to
three hundred and stops there, and a corridor at a hundred and twenty
was a firebreak down the middle of the school: a fire poured into it
went out in two minutes having reached one classroom. The houses do not
burn at all now — a shell has nothing to hold fire — though their yards
do, and the siding facing a burnt yard chars with it. A PARTY WALL is
still a wall fire gets through, at a tenth of the ordinary chance,
between two regions that both say they are one; nothing in the town says
so any more, and the supermarket's partitions never did.

WHAT IT COST, AND WHAT WAS DONE ABOUT IT
- - - - - - - - - - - - - - - - - - - - -

Fifteen and a half thousand regions against 327, and thirty-six
thousand lines against a thousand — more than the town with interiors
had, because a recess is four lines for one small room, the ground under
every eave is two regions where it was one, and every kerb that goes
round a corner is a square cut in two. Four things break at that size and all four break
quietly, so all four were fixed against the map that existed, before
there was a town to find them with:

  RECTMAP WAS EVERY RECT AGAINST EVERY OTHER RECT, twice — once for the
    overlap check and once for the edge splitting. A thousand rects is a
    million comparisons and nobody notices; fifteen thousand is two
    hundred and twenty-five million and is ten seconds of a half-second
    budget. Both are bucketed on a 512 grid now.
  THE FUEL GRID ASKED SECTORAT ONCE PER CELL. Over a town that is half a
    million point-in-polygon queries. Each sector fills its own bounding
    box instead, first one wins, and a plain rectangle does not ask at
    all. The two agree on all 97,902 cells of the store, which the test
    checks by running both.
  THE GEOMETRY WAS ONE BATCH PER TEXTURE for the whole map, which gives
    every batch a bounding sphere the size of the world. A batch is one
    texture in one BLOCK now; the portal flood's visible regions decide
    which blocks are drawn, and a block's indoor surfaces are a group of
    their own that comes in at two block pitches.
  AND THE CHAR REBUILD REBUILT EVERYTHING. It rebuilds the block that
    charred.

The startup is about a second and a half where it was half a second, and
most of what remains is honest: ten thousand polygons have to be
triangulated and a blockmap has to be built over them. The promise was
always about there being no install and no build step, and there is
still neither.

WHAT IS NOT IN IT is at the end of this file, and the short version is
that nobody lives there. No residents, no cars moving, no crowd on the
streets. Two in the morning is the excuse and it is a good one for a
first pass; it will not survive a second.


THE ART
-------

The store's own art is not an image file anywhere. Two reasons, and the
second is the real one: it loads instantly, and everything comes out of
the same box of parts so it all matches. The light comes from the top left in every
texture and every sprite — a rule, not a parameter, because a rivet lit from
the left next to a panel lit from the right is the loudest way to make a
wall look wrong.

MAX 64 PIXELS, everywhere. That is not a limitation, it is the brief. What
survives the cut, in every texture: one big shape you can read across the
store, one lit edge, and dirt at the bottom. Anything finer is gone by the
second repeat.

SOME THINGS ARE NOT DRAWN BY CODE, and could not be. It began as two —
the LOGO, because a procedural approximation of somebody's logo is not
their logo, and the WEAPON, because it is a photograph of a piece of kit
and there is no set of primitives that gets you there — and the argument
turned out to generalise. There is no set of primitives that gets you to
weathered granite, or to wrought iron, or to a lime tree, either. So the
list now runs: the logo, the weapon, EIGHT HEADSTONES, ONE PANEL OF
CEMETERY IRON, SIX BROADLEAF STREET TREES, A BLOCK OF CLIPPED BOX and
ONE STREET LAMP.

They live in art/ as PNGs and tools/bake-art.mjs turns them into source —
cut out (by brightness for the logo, by chroma key for everything else),
resampled, snapped to the game's own 256 colours, run-length encoded into
js/art-data.js. Nothing is fetched at run time and there is still no
build step: the build step is that file, run by hand, when the art
changes.

THE HEADSTONES GO IN THROUGH THE SPRITE BANK and the iron through the
texture bank, off the same decoder: decodeArtTile in js/sprites.js reads
a tile out of art-data.js, cutoutPix names one, and from there a stone is
eight frames of a GRAVESTONE actor and the iron is T.RAILING. The stones
were photographed with TEST cut into them, which is a word the game would
have carried into every graveyard in the town; eraseLettering in the
bakery finds the darkest band of rows relative to a blurred baseline and
patches it with clean stone copied from below. It is the rule the
shopfronts keep — no name on anything, ever.

THE CHURCH IS BUILT OF STONE, at the user's request, and it is drawn
rather than photographed: coursed ashlar, squared blocks sixteen to a
course with the perpends staggered against the course below, a lit arris
along the top of every block and the bed joint in shadow under it. It
was white clapboard, which is a true thing about a certain kind of
meeting house and was the wrong building — this one has buttresses, a
water table, a fieldstone foundation and a stone cornice under its
spire, and a clapboard wall between those disagrees with everything it
is attached to. Every exterior face wears it now: the nave, the tower,
the buttresses (which were a painted corner board) and the window
reveals. The roof stays shingle, because a stone church has a shingle
roof like any other.

AND THE STEEPLE HAS AN UNDERSIDE. A roof in this game is ONE-SIDED, like
every other surface: the slopes face out and from underneath a roof is
not there at all. That is right for every roof over a room, because what
is under it is a ceiling and you see the ceiling — and it is wrong for
exactly one thing, which is the spire, because the spire stands on the
tower's cornice over a storey that is SHUT. Stand in the churchyard,
look up, and you saw straight through the steeple into the sky. A roof
may now say what its underside is made of and gets a flat cap at its
springing, facing down: a boxed soffit, which is what a real steeple has
and is where a real one stops.

THE STREET LAMP GOES IN THROUGH THE TEXTURE BANK TOO, as two tiles, and
nobody hangs it on a line: js/mapgeo.js stands the pair up as a flat
cut-out on every STREETLAMP thing the town lays. It has a section of its
own further down — THE STREET LAMP IS A PHOTOGRAPH, AND IT IS NOT A SPRITE
— because the reason it is not a sprite is the interesting part.

THE TREES AND THE HEDGE GO SOMEWHERE ELSE, because js/forest.js does not
read art-data.js: it loads a PAIR of PNGs per plant out of assets/forest/,
an albedo and a BURN MAP, and that is the format the wood has had since
there was a wood. tools/bake-plants.mjs writes that pair. R, G and A of
the burn map come straight off the artwork — a green texel is foliage and
chars hard, a brown one is trunk and holds its coals — and B, which is
WHEN a texel catches, is invented from one sentence: fire starts at the
foot and goes up and out. Neither bakery is in CI; bake-art.mjs is
checked by re-running it and diffing the source it writes, and
bake-plants.mjs writes PNGs, where two zlibs that disagree by a byte
would fail a diff nobody could act on.

NONE OF THEM GETS AN EXEMPTION FROM THE 64-PIXEL RULE. The logo and the
weapon get GEOMETRY instead; the iron is baked at 64x64 and DECLARED 96
tall, which is the same trick every tall texture in js/textures.js uses,
and the stones are sprites, which are twenty-eight texels across. The
lamp gets both: two tiles, a head 64 across and a post 24, each declared
at the lamp's own size, and cut where the thing is rather than on a grid
— see bakeLamp in the bakery for why not one tile and why not eight.

The logo is four 64x64 tiles hung as a two-by-two on the
entrance tower — two ceiling steps for the rows, one vertical split for
the columns — because a sector engine cannot draw a big picture but it
can draw four small ones next to each other, which is the same thing and
is how every large sign in Doom was done. The weapon is one tile with its
top third left empty, and that empty third is where the muzzle flame is
drawn, in code, per frame: one still gun and a separate flash, exactly
how Doom's weapons worked and why they only ever needed one drawing.

THE FIRE IS DRAWN, and js/fireart.js is the whole of it: the flame on a
shelf, the blaze a gondola becomes, the ember guttering afterwards, the
fire climbing a fir, the pilot light and the muzzle flash. One generator,
four sizes, so all of it is visibly the same fire.

IT IS A CHAIN OF CIRCLES — a ball at the foot and smaller ones going up
to a point — with a noise field scrolling upward that eats into the edge
and pushes tongues out of it, and an axis that sways, anchored at the
foot and loosest at the tip. Brightness is banded into eight steps, which
is the difference between a painted flame and an airbrushed one.

THE ROUND BOTTOM IS THE INVARIANT and it is why the file exists. The
widest circle is the LOWEST one, so every circle above it is smaller and
sits higher, so nothing in the chain can reach below the foot and the
underside of the shape is the underside of one circle. It cannot come out
flat. What was there before was four painted strips from the golf project
put through a mask that pinched their feet in from the sides — and a mask
cannot round a bottom, because narrowing a flat edge leaves a narrower
flat edge. Measured the only way that means anything, column by column,
the strips' bottom edge rose four per cent of the flame's width from the
middle to the sides. These rise thirty.

AND IT LOOPS EXACTLY, which the PSX Doom routine that used to be here
could not: that is a simulation, and a simulation cannot be made to come
back to where it started. Something is alight for most of the game, so a
pop once a second is the thing a player would notice about the fire. The
noise lattice wraps after a whole number of rows and the scroll over a
loop is exactly that distance, so the last frame hands back to the first
with nothing moving.

THE PEOPLE ARE STANDEES, and there used to be a whole machine here for
making them something else. Two staff monsters, the Zombieman and the Imp
with the numbers filed off, built by posing a small articulated figure in
3D and flattening it to eight views per frame, then replaced by Freedoom's
player sprite with a smiley face over the visor and an apron painted onto
the armour. All of it is gone — the figure, the rig, the walk cycles, the
hundred and two frames, the two Python scripts that painted them — and
what stands in the aisles now is seventeen painted characters out of
github.com/verdictzero/galvarius, one drawing each.

One drawing each is the whole design and not a corner cut. Eight rotations
faked by mirroring one view look wrong from seven of the eight. A walk
cycle faked by sliding one drawing about looks wrong from all of them. So a
shopper does not walk, and every side of one is the front — which is how
Doom drew anything it only had one picture of, and it is what the actor's
`flat` flag has always meant. (The SWAT are the exception and the proof:
they were DRAWN from five sides, so they turn — see below.) They SWAY instead: two sines phased off the
actor's own id, an inch and a half of lean and half an inch of bob, in a
direction that also comes off the id so that no two of them move together.
It is a drawing offset and nothing in the simulation moves. On the title
screen, where the world is not being stepped at all, they are perfectly
still, which is what the title screen is for.

Seventeen people, thirteen pieces of one, three splats and twenty-six
frames of fireball come over in four STRIPS: one picture per kind, equal
cells, laid out left to right. tools/prep-people.mjs writes them and
js/people.js declares the cell sizes both sides agree on, so there is one
set of numbers rather than two that have to match.

Getting somebody else's art down to this game's scale is mostly one
decision and one trap. The decision is to scale every character by the SAME
factor — worked out from the 575 pixels a standing adult is drawn at over
there — rather than stretching each to a common height: three of these
drawings are of somebody crouching or sitting, and normalising by height
would stand them up into giants. The trap is the filter. A box filter that
averages colour and alpha separately drags the colour of every transparent
pixel into its neighbours, and at ten to one that puts a halo of whatever
was in the margins around every character; multiplying by coverage first
and dividing back out afterwards is the fix, and the alpha then gets a
small gain because a limb four pixels wide arrives as four tenths of one.

The fireball is the one set that is NOT trimmed to its contents. Its thirty
frames are one drawing moving inside a fixed window — the ball leaves the
ground, climbs, spreads — so the window IS the animation, and trimming each
frame would scale them all back to the same size and turn a rising mushroom
into a flickering still. It is resampled to twenty-six because a frame is a
letter and the letters stop at Z.

THE SWAT ARE THE USER'S SHEET, and the first people in the game with
ROTATIONS: eleven rows on a magenta ground, the first seven of them five
views of one pose — head on, a quarter turn, side on, three quarters, from
behind — and the rest a death, three frames of lying there and nine of
coming apart, drawn from the front only. That is Doom's own economy
exactly: five drawings, and rotations 1, 2 and 3 are the mirror of 7, 6
and 5, which js/people.js says in a table (SWAT_ROTATIONS) and
Pix.mirrored does. A trooper walking away from you shows you his back,
which no shopper can, and it is the whole of what makes a thing you can
walk round read as a thing rather than a card.

tools/prep-troops.mjs cuts it (it was tools/prep-swat.mjs until a second
sheet arrived; see THE ARMY TROOPER below), and two things about that were
harder than they sound. THE SHEET IS A JPEG, so the magenta is not a colour but a
cloud of them and every edge carries a halo where the ground bled into the
ink; the tool measures how magenta each pixel is, spends that number as
the pixel's transparency, and unmixes the magenta back out of what colour
is left, so a halo pixel a third magenta becomes a two-thirds-opaque
pixel of the colour it was hiding. AND THE CELLS ARE NOT ON A GRID: the
widest side view is twice the width of the narrowest back view and the
lying frames are stacked three high in the last column, so the cells are
FOUND — an XY cut, splitting on empty rows and then empty columns and
again until nothing splits — with one seam found by hand, where the death
row's blood reaches the gore row under it. Sixty tall, a shade under the
crowd's sixty-two, because the frame of somebody coming apart is taller
than the somebody and the sixty-four-pixel rule is a rule.

THE ARMY TROOPER IS THE USER'S SECOND SHEET, prepared the same way and,
at the user's request, NOT YET IN THE GAME. Same artist, same eleven rows
in the same order — seven poses in five views, the fall, the three lying
frames stacked in the last column, the nine of coming apart — on the same
magenta, as a JPEG again, decoded in a browser to art/people/army_sheet.png
and cut by the same tool into assets/people/army.png: fifty-one cells,
sixty-four square, in the order the SWAT's are. The tool is driven by a
table now (TROOPS in js/people.js: which sheet, which strip, how tall,
how much lift) and the SWAT strip it writes is byte for byte the one the
old tool wrote, which was checked when it was renamed. THE SAME SIXTY
TALL, so the two stand level side by side — and at that scale three of
the army's floor frames, the last splatter and the two pools a body ends
as, come out sixty-five, seventy-one and seventy-two across against a
cell of sixty-four. The SWAT's sheet happened to fit; this one does not,
by a few columns of the thin smear at a pool's edge. Scaling the whole
figure down until the pools fit makes a trooper fifty-three tall beside a
SWAT at sixty, so instead a FLOOR frame — never the figure — may lose up
to eight columns off its two edges, and the tool says what fraction of
the ink that was: a tenth of a per cent of the splatter, four per cent of
one pool and two of the other, all of it the tail of a smear. A QUARTER
OF THE LIFT is the
other number of the army's own — 0.85 against the SWAT's 0.62 — because
the tone curve that rescued
navy from the dark would turn tan and olive pale: the army figure is drawn
three and a half times brighter in linear than the SWAT to begin with, and
the tool prints the figure's mean before and after so the next sheet can
be set by the same number. addTroops reads either strip back into the
bank under its own name, the smoke test proves both, and that is the
whole of what exists: no actor, no states, nothing loads it, and the
letters mean nothing until there is one. When there is, THE SWAT in
js/states.js is the table to copy, letter for letter.


THE CAR PARK IS ONE VAN, THREE DOZEN TIMES, at the user's request, and
it arrived MODELLED — a GLB, dropped in as it is. There is no other kind
of vehicle in the project now: the system that built seven of them out of
four drawings each is deleted, and there is an obituary for it further
down, because it was a good piece of work aimed at the wrong question.

WHAT IS LEFT IS SHORT. The file's own triangles, its own UVs, its own
texture, drawn both sides. A second GLB would drop in beside this one
with no new code at all, which is the thing the old system could never
say — and then one did, the police van, and it cost eight lines: the
loader was taking the FIRST image in the file for the sheet, and the
police van arrives with four (emissive, normal, diffuse, metal-rough, in
that order), so the first cut of it was painted with a flat black
emissive map. A GLB says which picture is the colour — the material's
baseColorTexture — and the loader asks it now. See THE ROAD, AND WHO
COMES DOWN IT for what the van does.

AND THEY ARE NOT ALL THE SAME COLOUR, at the user's request. One model
in every bay is a delivery fleet, which was a joke worth exactly one
look; a car park is what this is meant to be, and a car park is a dozen
colours of the same few shapes. It is still one model, one texture and
one draw call — that was the thing worth keeping — so a red van is not
a second file. It is the same texel, multiplied.

THE WHITE IS ISOLATED IN THE SHADER, out of the texel itself, rather
than painted into a copy of the sheet by hand. The van's paint is white:
bright and dead neutral. Everything that must not take the colour — the
grille, the bumpers, the tyres, the glass — is far darker. So a
luminance ramp with a saturation guard picks out the bodywork exactly,
and it does it per TEXEL, which is the whole reason it looks like paint:
every bit of shading the artist put in the sheet survives, so the
shadowed flank of a blue van is dark blue and the lit roof is bright
blue. A flat colour over the body would have thrown all of that away.
Nineteen per cent of the sheet is paint, eight per cent is the shading
on it, and the shading takes a part of the colour, which is the bit that
sells it.

THE COLOUR RIDES IN A CHANNEL THAT WAS ALREADY THERE. Every vehicle
vertex already carried an `ink` — what an untextured surface is painted,
for the flat materials glTF allows, with a flag saying whether to use
it. When the flag is off, the three numbers beside it were zeroes saying
nothing. They are the paint now. One attribute, two meanings, no new
bytes: a surface with no picture IS that colour, and a surface with one
has its white multiplied by it.

IN LINEAR, AND THAT IS THE WHOLE TRAP. The sheet is an sRGB texture and
is decoded on the way out of the sampler, so the numbers in the shader
are not the numbers a colour picker says about the PNG. Set off the file
— paint at 0.75 to 0.94, ramp from 0.55 — the ramp caught only the
brightest highlights, and what came out was a white van with a red
pinstripe down every edge. Measured in linear instead: background 0.06,
tyres and grille under 0.09, glass 0.28, the darkest shadowed paint
0.53, a lit panel 0.67, the roof 0.78. The ramp goes between the glass
and the shadow.

WHICH BAY GETS WHICH is a hash of the bay's own position and not a fresh
random, for two reasons: the map lays the lot out with its own seeded
stream and drawing from it here would move every number after it, which
is most of the level; and a fleet that is the same fleet every time the
level is built is a fleet you can take a screenshot of twice. The quiet
colours are in the list twice, which is the cheapest weighting there is
— a real car park is mostly white, silver and beige with a few colours
in it, and a list sampled evenly puts a turquoise van in every eighth
bay.

AND NOTHING IS AS DARK AS A VAN REALLY IS, because this multiplies
twice: the sheet's own shading, and then a car park at dusk on top of
it. The first palette was picked at the values a van is actually painted
— 0.24 to 0.6 — and the lot came out as two whites and ten grey shapes
with wheels.

WHAT A MODELLED VEHICLE NEEDS, AND IT IS NOTHING. There is no
preparation step and no tool: assets/models/van.glb is the author's own
export, byte for byte, and js/car.js reads it as it stands. It walks the
scene graph, multiplies the node matrices through, puts the triangles
into the space the game speaks — x +0.5 at the nose, y to the vehicle's
left, z 0 on the ground, all as fractions of the length — and measures
the width and height off the triangles themselves, which is what the
collision and the tumble want. The ONE number that is not in the file is
how long a van is in game units, and that is a fact about the game rather
than about the model: a bay is 186 across and a shopper is 62 tall, so
VAN_LENGTH is 174 and everything else follows from the model's own
proportions.

THERE USED TO BE A TOOL. tools/prep-van.mjs halved the texture, snapped
it to the game's 256 colours, painted a dark block into a corner of the
sheet for the untextured triangles to point at, and wrote the axes it had
measured into asset.extras. All of it is deleted, at the user's request:
the model's textures and UVs are deliberately configured as they are, and
a game that rewrites an asset on the way in is a game arguing with its
own author.

THE MODEL'S OWN UVs ARE USED, and getting there took four attempts, three
of which shipped. The mesh is unwrapped onto the very sheet embedded in
it, which is why it renders correctly in Blender and on Sketchfab, and
for three rounds this game painted it by projection instead — on the
strength of a measurement that said the flanks were a fan of long thin
triangles all sharing one corner.

That measurement pooled BOTH primitives of the van of the day. The
flat-black one had no texture, so its UVs were unused junk — 490
triangles "covering" 321 per cent of the sheet, which cannot be a layout
at all — and the junk was the fan. Drawing the UV layout over the texture
PER PRIMITIVE is what finally showed it; drawing it over both at once is
what hid it.

THE VAN IN THE LOT NOW IS ONE MATERIAL AND ONE UNWRAP, and every triangle
of it is on the sheet: 1,050 of them over 38 per cent of it, the biggest
covering one per cent. The layout is a four-view PROJECTION drawn into
the file — the flanks onto the side elevation, the roof onto the plan,
the nose and the tail onto theirs — which is the same mapping the deleted
fleet used to compute, made by hand by somebody who could see it. It is
also what made the next bug visible in one screenshot.

WHICH WAY UP THE SHEET GOES, and this one stood for a whole model.
glTF puts v's origin at the TOP-LEFT of the image and GL puts t's at the
bottom, so exactly one turn has to happen somewhere. There were two:
`1 - v` on the way out of the model AND `flipY` on the texture, which
looks symmetrical, reads as careful, and is wrong — `flipY` is quietly
IGNORED for an ImageBitmap, which is what a texture packed inside a GLB
is decoded into. So one turn happened instead of two, and every panel of
every van in the car park wore the wrong half of its own sheet: flanks
painted with the front elevation, grille and headlights down the side.

Nothing caught it because nothing could. The van it was written for had
134 textured triangles on a sheet of white bodywork and 490 flat black
ones over them, and a white van painted with the wrong view of a white
van is still a white van. Replacing it with a model unwrapped all over
put a radiator grille down the side of thirty-six vehicles at once.

The sheet goes up the way it is stored now — `flipY = false` and the
model's own v untouched, which is what js/glb.js had always done for the
gun — and the smoke test pins BOTH halves, because either one alone is
the same trap set again.

AND IT IS DRAWN BOTH SIDES, which was the other half of the same lesson.
The file declares which way a face points twice — the winding of its
corners and the NORMAL on them — and both declarations disagree with the
SOLID: this shell comes to minus a quarter of its own bounding box, which
is a surface wound inward. The van before it was two shells wound against
each other, the body at minus a third of its box and the chassis at plus
a tenth, and the first attempt at a fix was a single flip: reverse
everything when the total volume comes out negative. That turned the body
the right way out and the chassis inside out with it, and the car park
went from vans seen from the inside to vans with no bodywork.

The model is not wrong. Blender and Sketchfab both draw BOTH SIDES of a
single-sided material by default, and that is the entire oversight — this
renderer culls back faces, and the model was authored where that never
mattered. Vehicles are double-sided now, the winding is left exactly as
the file has it, and a vehicle is a thin shell you are never inside, so
the cost is drawing the far face of a solid that already covers it.

The NORMALS are still turned outward from the model's own centre, 582 of
the 1,050, because the face light reads them: Doom's fake contrast wants to
know whether a face is a roof, an underside or a flank, and a roof
triangle whose normal points down is given the tarmac's light, which is a
third of the brightness. That IS a heuristic, and it is used for the
light and nothing else — a triangle it guesses wrong about is one step of
shading out on one face. It can no longer cull anything or choose
anybody's paint, which is exactly what made the same guess fatal when the
projection depended on it.

AN UNTEXTURED MATERIAL RIDES IN THE VERTICES, which is how the car park
stays one draw call. The van in the lot has no such material — all 1,050
of its triangles are on the sheet — but the one before it was two: the
body, unwrapped, and van_black, which was glass, tyres, bumpers and
chassis, 490 of its 624 triangles, with no texture at all and just a flat
baseColorFactor of 0.0059367 linear, about 18 of 255 on a screen.

glTF allows that and so does the reader, because a second material is a
second draw call for every slab of parked cars. Every vertex carries the
colour ITS OWN material declared plus a one-or-nothing saying whether to
use it, in an `ink` attribute, and js/material.js mixes between the sheet
and that colour in the fragment shader. The number goes through
UNTOUCHED: baseColorFactor is linear and an sRGB texture is decoded to
linear when the GPU samples it, so both sides of the mix are already in
the same space. The deleted tool used to paint a lifted version of that
colour into a corner of the sheet and point 490 triangles at it.

With nobody using it the path would rot, so it is held against a
hand-built two-primitive file in the smoke test rather than deleted for
want of a user: drop in a model that declares a flat colour and it still
comes out wearing it, through the clip and into the debris.

AND WHICH END IS THE NOSE IS IN THE FILE AFTER ALL — in the format, not
in the asset. glTF says +Y is up and that the front of an asset faces +Z,
so the nose is +Z and the left flank is +X, and the swap from (z, x, y)
to (nose, left, up) is a cyclic permutation that preserves handedness.
This used to be established by rendering four orthographic views in a
scratch script and looking at which end had the grille in it, which is a
fine way to check a convention and a poor way to have one. The only thing
asserted at load is that the model IS longest along +Z, because a van
that is not is a van exported facing some other way, and the honest time
to find that out is the moment it is read.

AND THE TEXTURE IS THE FILE'S OWN, at its own size. It is a 512x256
four-view turnaround — front, rear, side and plan on a flat grey field —
used as it is. The model is 198K, of which 158K is that PNG, and it is
downloaded once.

BUT IT IS POINT SAMPLED WHETHER IT ASKS TO BE OR NOT, at the user's
request, and so is every other model this game imports: NEAREST
magnified, NEAREST_MIPMAP_NEAREST minified, which is exactly what
js/textures.js does to the walls and floors. This renderer point-samples
everything — the walls, the sprites, the sky, the fire, the HUD — and the
whole look of the game is downstream of that.

It used to be the file's own sampler, on the grounds that a model is a
self-describing thing and its author had an opinion. The van agreed with
the game, because it is exported NEAREST, so for a long while there was
nothing to notice. Every model since has asked for LINEAR — which is
simply what a modelling program writes by default — and got it: five of
the six, the gun in your hands among them, were going through a bilinear
filter that softened them against a world that is not soft. Held side by
side at full resolution with one property flipped, the lettering down the
flank of a police van goes from feathered to hard-edged and the frame
carries fourteen per cent more edge.

Mipmaps stay ON, which is the one part that is not simply "nearest".
Without them a minified surface boils into aliasing noise as it moves,
which is a different artefact from the one Doom had and not a better one;
with them a van at the far end of the lot picks one mip level and samples
it sharp. The sprites get no mipmaps for a reason of their own — a mipped
sprite loses its cut-out edge — and a model is not a cut-out.

WHAT IS STILL THE FILE'S IS THE WRAPPING, because that is not a question
about how the game looks, it is a question about what the UVs mean: a
model unwrapped to tile across a seam needs REPEAT and one unwrapped into
an atlas needs CLAMP, and only the file knows which. Where a glTF says
nothing the spec's own default is taken and not this renderer's habit,
which is how wrapping ends up REPEAT.

It is one function — pointSample in js/glb.js — called from both places a
model's texture is built, because the vehicles come through js/car.js and
the guns through js/glb.js and a rule that only half the models obey is
not a rule. There is no filter table in either file any more.



THERE WAS A WHOLE SYSTEM HERE and it is gone, at the user's request, so
what follows is an obituary rather than a description. It is worth one,
because it was a good answer to a question nobody was asking by the end.

WHAT IT DID. Seven vehicles arrived as orthographic turnarounds on a
green field — front, rear, side and plan, a hatchback, two white vans a
model year apart, a pickup, a custom van with an eagle down its flank, a
riot van and a tracked APC. tools/prep-car.mjs keyed the green, measured
each sheet and wrote js/car-data.js: proportions, and three curves that
between them are the VISUAL HULL of the three silhouettes. js/car.js put
a vertex at every crossing of those curves and painted every triangle by
PROJECTION — take the axis a face's normal points most nearly along, read
the view that was drawn down that axis, and the pixel lands where it came
from. No unwrapping, no seams, no atlas authored by a person. Four
pictures in, a solid out, and the debris got real paint for free because
a torn piece was a box cut out of the same model space and put through
the same projection.

It was over-determined, too, which is the part that was genuinely nice:
three of the four views claim the vehicle's width, so each sheet could be
checked against itself, and the check caught a sheet that was not one
vehicle, two sheets drawn facing the other way, a right flank painted
with its tail at its nose, and a wheel measured off a bull bar.

WHY IT IS GONE. Because the car park stopped being four pictures and
became a MODEL, and a projection that infers a mapping is strictly worse
than a mapping somebody already made. Three rounds of trouble came out of
that mismatch and every one of them was the projection arguing with a
file that already knew better: the flanks smeared (the measurement that
condemned the model's own UVs had pooled them with a second primitive's
junk), the vans inside out (the projection reads a normal to choose a
picture, so an inverted normal paints a panel with the opposite panel),
and then the vans with no bodywork (the fix for that was a global winding
reversal, and that mesh was two shells wound opposite ways).

So js/car-data.js, tools/prep-car.mjs and art/vehicles-atlas.png are
deleted, along with the hull builder, the projection and about a hundred
and fifty checks that held them together. The seven sheets stay in art/,
unshipped, in case anybody wants them back. js/car.js is a fifth of the
size and does what the file says.

WHAT REPLACED IT IS NOTHING, WHICH IS THE POINT. The GLB's own nodes,
its own triangles, its own UVs, its own texture, its own material
colours, drawn both sides. There is no tool between the file and the
game: the length in game units is a constant in js/car.js, and the width,
the height and the ground line come off the triangles at load time.

THE PIECES COST SOMETHING, and it is the only thing that got harder. A
chunk used to be a fresh box with the views projected onto its six faces,
so it was small by construction. Now it is the model's own surface inside
the cut, and the first attempt at that — whole triangles, in or out by
their centroid — sheds roof panels two thirds of the van long, because a
whole van's body shell is 134 triangles. So the pieces are clipped
properly: Sutherland-Hodgman against the six planes of the cut, carrying
u and v along with the position, fan-triangulated. Forty lines, and a
piece is a piece.



YOU CANNOT WALK THROUGH ONE. Doom's things are cylinders — one radius, no
rotation, however long the thing is — so five and a half metres of van is
three of them in a row, which is the oldest trick in the format and still
the right answer. That leaves the corners a few units short and the flanks
a few units proud, and a shopper brushing past reads it as a van. Those
cylinders are the only actors in the game with NO STATE and no sprite:
they have no `spawn`, so Actor.render and Actor.tic both fall out on their
first line. Each one carries a pointer back to its vehicle and hands
everything done to it straight over, because a shot into any third of a
van is a shot into the van, and health that lived in the cylinders would
make a van take three times the punishment and come apart in thirds.


AND THEN IT GOES UP
-------------------

A car is flammable and shootable, so the flamethrower lights it, the fire
under it keeps it lit, and about four seconds later the tank is done for.
What follows is one sequence and every part of it is arithmetic you can
read.

IT CHARS FIRST, at the user's request. A car used to go from parked to
airborne in the tic its health ran out; now the tank going is the END of
something you watch. For five to seven and a half seconds — rolled per
car, so a row lit together does not go off like a firework display on one
fuse — the car leaves the slab for a mesh of its own, the only way to
change one vehicle's vertices without rebuilding thirty-six, and two of
its attributes are wound by hand: `charred`, which js/material.js scatters
live coals across in proportion, and `light`, which comes down to under
half so the paint goes black beneath them. Sparks off it the whole time,
more as it goes; smoke, thicker; and the one fire light pulled toward it,
harder as it goes, so the bay round a car about to go is lit like a
hearth. More damage to a car already charring HURRIES it — two tics off
the fuse a point — so a chain reaction across a full row is a ripple
rather than a metronome. It is a wreck arriving gradually, and when it
reaches the end it goes up on the geometry it has, so what is in the air
is the black thing you watched turn black.

THE FIRST BANG IS FOUR OF THE OLD ONE, also at the user's request, and
four is spent where four can be seen: four times the fireballs, spread
past the car's own footprint rather than four times as many in the same
square, four times the embers and the smoke, the heat of the floor pinned
to the top of its scale, a light thrown at the bay and decaying over the
next second so the whole car park is lit from it for a moment and then is
not, and a sound made the loudest thing in the game. The RADIUS is doubled
rather than quadrupled — a doubled radius is a quadrupled area, which is
what four times the blast means on a floor plan — and the damage is
doubled, which with the area is eight times what the old bang put into the
car park. It damages and IGNITES everything within four hundred and
twenty units, clears the car park of anybody who can be frightened, and
puts the car in the air. The second bang, where it lands, is what it
always was.

THE TUMBLE IS NOT A PHYSICS ENGINE and does not want to be. It is a
velocity and a gravity of 0.85 units per tic per tic — the same fall the
sparks off a broken light take, which happens to be very close to a real g
at this world's scale — plus three spin rates integrated separately as
Euler angles in the order the mesh is built for: yaw, then roll about the
car's own length, then pitch nose over tail. That is not rigid-body
dynamics and for a car in the air for forty tics nobody can tell.

IT LANDS ON ITS ROOF BECAUSE THE ROLL RATE IS CHOSEN SO IT WILL. The
flight is ballistic, so how long it will be up there is known the moment
it leaves the ground: a box turned half a turn about its own length is
exactly as tall as it was, so its middle comes back to the height it
started at and the flight lasts 2v/g. Divide half a turn by that and the
car completes its roll as it arrives. It is aimed, not simulated, and it
is the difference between a car that lands upside down and a car that
lands upside down SOMETIMES.

HOW HIGH A CAR ON ITS ROOF SITS is not a number anybody types in. The
eight corners of its own box get turned by whatever orientation it has and
the lowest one is put on the tarmac — which works at any angle, so the ten
tics it spends rocking from however it hit onto its roof are just the same
test run every tic while the orientation eases to its resting one. It ends
up half a turn over and a few degrees crooked, resting on a corner of its
roof and its bonnet, at whatever height that leaves it.

THE SECOND BANG happens on impact, and with it the bulk of the debris.

THE DEBRIS IS MADE OF THE CAR. A chunk is a small box cut in around a
random point on that vehicle's own hull — a bit of roof, a bit of
bonnet, a bit of door — and put through exactly the same projection, so
a piece off the tail is painted with the tail on every face and nobody had
to decide what a torn piece of van looks like. Each one tumbles on the
same integrator, bounces once if it came down hard, snaps flat to the
nearest half turn when it stops — a piece lying still would otherwise go
on spinning for ever — and then lies there throwing sparks and smoke for
twenty seconds. After that the particles stop and the coals do not,
because a wreck and every piece of it are built with `charred` set, which
is the attribute js/material.js scatters live embers across: the same ones
burning in the gutted aisles indoors, on the same clock.

AND THE CAR PARK GOES UP A BAY AT A TIME. Nobody wrote a chain reaction.
Cars are flammable and explosions light what they reach, so the bay either
side catches, cooks for its own few seconds and goes in turn, and a row of
them is a wall of fire inside a minute. It is the same emergence the store
has: the thing that makes a fire game a fire game is that you only ever
light the first one.

THE TEST
--------

  node tools/smoke-test.mjs

No install and no browser — a stub stands in for three.js, since the
bakeries, the map builder, the collision and the state tables are all pure.
2612 checks. Every one of them earns its place by having caught something
that had already reached a screenshot:

  a sprite whose art wrapped round the edge of its own canvas, so a forearm
    drawn off the bottom appeared in the sky, at a fixed point on screen,
    in every shot
  a state naming a frame letter the bakery never made, so a monster's
    pain frame did not exist — and its descendant, which is that an actor
    with `variants` never draws the sprite its state names at all, so the
    check expands SHOP into SHO0 through SHO16 and a missing sixteenth
    shopper cannot hide as one magenta person in a crowd
  a wall texture chosen by whichever sector was DECLARED first, so an aisle
    had shelving down one side and blank plaster down the other
  every tread face on every wheel of every vehicle wound inside out —
    sixty-four triangles a car, shipped, through a test that passed. The
    test could only decide a face with air on one side of it, and a tyre
    is buried under a wheel arch; and a back-facing tyre in a dark car
    park is a black shape either way. Now the builder emits every
    triangle the way round its declared normal says, the test holds the
    winding against that, and every solid must be closed — each edge
    shared by exactly one triangle going the other way — with a positive
    volume about the size of a car. None of that needs air or guessing
  a third of the fleet built back to front, because two of six sheets
    were drawn facing the other way and the tool assumed one direction
    for all of them; every right-hand flank painted with its tail at its
    nose, on the theory that a mirrored picture needs mirrored
    coordinates; and then the hatchback declared the wrong way round by
    eye, and caught by its own top edge
  the roof line diving into a rear window, because the opened mask that
    is the right ruler for the box thins a pillar to nothing, and a
    window with no pillar reaches the sky
  seventy-seven cars parked on the bay lines instead of between them,
    because the texture that draws those lines tiles from the world
    origin and the car park does not start there
  a white van that came out pale green, because a green screen throws
    green light on what stands in front of it and the eye only forgives
    that while the green field is still there to compare against
  a wheel measured off a bull bar, which made each tyre four tenths of
    the van long
  a move long enough to step clean through a wall with nothing noticing it
    had been there
  a hard fuel threshold that stopped fire crossing a walkway at all, which
    meant most of the shop could never burn — the check demands every
    region of the store, and demands that every region says so
    afterwards. It used to prove that with ONE MATCH left for forty
    thousand tics, and cannot any more, because a match now goes out:
    it walks a flamethrower over the whole shop instead, which is a
    claim about whether the store CAN burn rather than whether it does,
    and that was always the claim the floor plan was written against
  the same sweep done at molotov strength, which quietly torched the car
    park. Anything over 40 leaves accelerant behind, and accelerant
    poured on tarmac makes tarmac burn — so a sweep with a generous
    number would have taken the "a sector with no fuel never burns"
    check down with it and called it a pass. It pours 36, which is what
    the flamethrower actually lays
  an evacuation measured against a carpet bomb. The fire no longer
    empties a building on its own, so the check that the fire exits are
    load-bearing had to start lighting the shop itself — and painting
    all eleven aisles inside four seconds is not a player, it is an air
    raid: everybody is standing in fire before anybody has taken a step,
    five hundred and seventy die where they stand, and the doors get no
    chance to be load-bearing. It pours at a walking pace now, and the
    aisle ahead of you empties the way it does in play
  sector light measured to a bounding box, which pinned the whole shop at
    full brightness and made the lights unshootable in effect — the check
    now bursts every fitting over one aisle and demands it get darker
  a fixture texture whose declared world height did not match the fixture,
    showing a slice of a second copy of itself cut off at the floor
  a fixture whose TOP was gondola steel, on the one department in the shop
    you look down into rather than at
  a texture drawn with fractional pixel centres — which on a surface that
    wraps by modulo rather than flooring means a fractional array index,
    and a fractional index into a Uint8ClampedArray writes NOWHERE. No
    error, no pixel: every crate of produce came out as bare liner
  a firebreak check phrased as "no outdoor sector burns", which stopped
    being the same statement the moment the store got a footway — the
    pavement is outdoors AND carries fuel, on purpose, because it is the
    fuse that takes the fire along the parade to the neighbours. The
    check is now the invariant the map is actually written against: a
    sector with no fuel never burns, whatever else is true about it
  a flame that stopped dead a hand's width from the nozzle, because the
    tree hit test took a fir's whole sprite width as solid down to the
    ground — every particle "hit a tree" beside the player and the splash
    embers spawned in the camera's face as thirty-pixel squares. The
    check now fires beside a trunk and demands the stream pass it
  a forest fire whose pace was a guess; the check runs one match for an
    hour of game time and holds it between a flash and an afternoon —
    and it caught the second tuning sitting on the percolation edge,
    where a match took or fizzled by luck
  a store fire quartered to please the ear, which stopped the footway
    carrying it along the parade; the neighbours never caught. The
    slowing moved to the fire's clock, which is what the clock is for
  a copy of the site that left out the fire strips, so the published game
    would have fallen back to its baked flames without a word — the check
    now assembles the site and holds every asset path the page loads
    against what was copied. The fire is drawn now and there is nothing
    left to leave out, but the check is what found it
  strips of somebody else's art whose cell sizes live in two places
    at once — the tool that writes them and the game that cuts them up.
    They now live in ONE place, js/people.js, and the check holds the
    files on disk against it: a strip one pixel narrow cuts every shopper
    after the first in half, silently, at load time
  a THIRD attempt to slow the fire that put thin fuel back under the
    percolation line — the footway stopped carrying the fire east along
    the parade and three of the neighbouring units could never burn at
    all. The check that caught it is now two checks, because it was
    making two claims at once: whether the fire GETS IN to a region is
    absolute, and whether it then eats the region is a matter of degree
    that a doorway four cells across cannot express
  a customer standing in the loading dock, which is not a thing a
    customer does. The map places the crowd through one predicate and
    exports the rectangle it used; the check holds every one of them
    against it from the other side
  two customers at the same coordinate, which is one customer with a
    shadow and, worse, two who can never move again: the move check
    refuses any step that ends inside somebody, so a pair placed already
    touching is a pair welded to the floor. The check measures the
    closest two in the shop and demands they be further apart than two
    shoppers are wide
  and a customer who is not overlapping anybody and still cannot move,
    which is not the same statement: thirty-six apart is not touching and
    is still nowhere to go, because a step is sixteen. The check asks
    every one of them for a step it could take
  a customer standing on top of a till, a gondola or the butchery
    found by testing the sector under them rather than the rectangle
    round the shop
  a hard straight line across the shop floor where a burnt aisle met a
    clean cross-aisle, reported as z-fighting and near enough: the soot
    read how far through burning a surface was out of a
    one-texel-per-SECTOR picture, and a sector's progress is one number.
    Every surface in one sooted together, and the sectors of this map
    are big axis-aligned rectangles, so the step landed as a knife edge
    — exactly vertical or exactly horizontal on screen, with a different
    texture and a different light level on each side of it. It reads as
    two surfaces fighting rather than as a fire. The shader reads the
    fire's own 32-unit cell grid by world position now, so the soot
    front creeps at the resolution the fire actually has and crosses a
    sector boundary without knowing it is there. The region attribute
    and its texture are gone with it: a surface finds its own burn from
    where it is
  a 40%-burnt aisle drawn as a black void with shoppers floating in it,
    because the soot took the albedo to a fifth and the room light took
    that to nothing. What a surface part-way through burning has to look
    like is set by what it hands over to, not by what a burnt surface
    reflects
  a burnt-out store with no ceiling anywhere, because the first gutting
    opened every region to the sky. The check now demands BOTH — some of
    the roof fallen in and most of it still up — since either alone is a
    different building
  a van with four of its faces wound inside out, which in a single-sided
    material is a hole you see the inside of the van through. The check
    steps a little way along every triangle's own normal and asks whether
    that lands inside the solid, which is the only phrasing that does not
    just restate the code that built it
  a van painted with a pale band along the top of its nose and its tail,
    because the head-on views draw it sitting lower in the frame than the
    side view does and the roof therefore landed in a band of the picture
    that is nothing but light bar. The views are anchored on the roof line
    now, and the check holds the top of the body against it
  a fire door that sealed the inside face of its wall and left the
    outside one open, which is a door you walk round from the car park.
    The check counts the blocked lines and demands two
  a fire door that opened for anybody who walked past it, so the shop's
    six of them stood open all night with nothing on fire. The check
    stands a calm shopper against the bar and requires nothing to happen,
    then frightens the same shopper and requires the leaf to move
  a crowd that could not calm down. Contagious panic passed on at full
    strength is a loop — six hundred people in the woods behind the
    store, none of them able to see a fire, each one renewing the
    neighbour who had just renewed them. What the check watches is not
    "is everybody calm at the end", because the count legitimately climbs
    again each time the fire reaches a part of the shop that still has
    people in it; it is the LOW WATER MARK after the first wave, which a
    loop can never reach
  a fire whose scatter was re-rolled every frame, which is not a fire, it
    is a fire boiling. The check renders the same frame twice and demands
    every sprite be in the same place
  seventy-seven vans with their flanks smeared, because the model's own
    UV layout maps every side panel as a fan of slivers sharing one
    corner. The check holds the widest single triangle's share of the
    sheet against a tenth of it: a fan collapses to nothing and a
    stretched sliver covers everything
  and then seventy-seven vans seen from the INSIDE, which was the real
    fault under that one and took three reports to find. The model
    declares which way its faces point twice, by winding and by normal,
    and its two declarations agree with each other and disagree with the
    solid; every face of the body was culled, and the projection painted
    each panel with the picture of the opposite one. The test measured
    the axes, the scale, the ground line and the UV spread —
    everything except whether the van was the right way out
  and then vans with no bodywork, which is the SAME bug fixed wrongly.
    The fix was a global reversal when the whole mesh's signed volume
    came out negative, and the mesh is two shells wound opposite ways:
    the body at minus a third of its box and the chassis at plus a
    twentieth. Reversing both put the body right and the chassis wrong.
    There is no single flip, and there did not need to be one — Blender
    and Sketchfab both draw BOTH SIDES of a single-sided material, which
    is the whole of what this renderer was not doing. A vehicle is
    double-sided now and the file's winding is untouched. The test
    reports both shells' volumes rather than the mesh's, which is the
    number that would have said so in the first place
  A FROZEN SHOPPER SETTING THE BEANS AISLE ON FIRE, which shipped for
    about ten minutes and is the funniest way this could have gone
    wrong. A burning piece of somebody trailed fire behind it and lit
    the floor where it landed — which was how a crowd MOVED a fire, and
    was one of the best things in the game right up until the day the
    fire was asked to stop spreading on its own — and the shatter reused
    that pool for its pieces. So the one weapon whose job is putting
    fires out, used properly on a person, started one. The pieces are
    the same art and the same ballistics; what they do when they arrive
    is the whole difference, so they are a second pool with a tic of
    their own that lands a splat and a breath of vapour and nothing
    else. The test shatters somebody and then runs two hundred tics of
    giblets and counts the cells that caught: none
  THE SAME BUG WEARING THE OTHER DOOR, found while checking that the one
    above had really been fixed. Fire is meant to be the counter to the
    extinguisher: it eats the frost, the person thaws, and what comes
    out the other side is alive and alight. That is what the manual
    above promises and what ignite() does — but a flame particle is TWO
    calls, ignite and then damage, and damage knew nothing about frost.
    So the melting and the hurting raced and the hurting won: a shopper
    has twelve health and a particle does five to nine, so the SECOND
    one killed them with forty-four of their hundred frost still on.
    They never thawed, never got up, and — because dying runs the
    ordinary death state — came apart into BURNING giblets that lit the
    floor where they landed, exactly the way the shatter used to. The
    extinguisher had been making people more flammable. Fire damage is
    spent on the ice now, at twice its value, and none of it reaches the
    person until the ice is gone; a blast carries enough to take the
    whole bar off at once, so a car going up beside a block of ice frees
    whoever is in it and then lights them. What let it hide is that the
    test drove ignite() on its own — the half that was right. It drives
    the real FlameStream._burnActor now, and asks what came out
  A CORPSE STANDING BACK UP WHEN IT THAWED, which nothing in the shipped
    game could reach and which is checked anyway. thaw() ends in
    setState(freezeReturn) — get up and run — and it ran on whatever it
    was called on. A shopper's death state removes them on the tic it
    runs, so there was never a body left to melt; the day something
    freezable has a death animation that lingers, there would be. The
    dead stop being blue and stay where they are
  A BLOCK OF ICE FOR SIX TICS. Freezing put the frost bar at the top
    and thawing took it off at a unit every six tics — and the thaw
    triggered the moment the number dipped BELOW the threshold, which
    it does six tics later. So a frozen shopper was frozen for a sixth
    of a second and then walked off. Freezing happens at the top of the
    dial and thawing at the BOTTOM of it now, so the whole bar is the
    time they spend solid and the state has hysteresis. The test freezes
    one, tics once, and asserts they are still frozen — and then counts
    how long it actually takes, which is about seventeen seconds
  A BLOCK OF ICE WALKING OFF DOWN THE AISLE, which is the same mistake
    as the one above made in a different place: freezing somebody
    stopped them moving THEMSELVES and nothing else. setState is the
    door every other system in the game reaches an actor through, and
    it had no lock on it, so all three of the things that make a crowd
    react reached straight past the ice: a car going up nearby
    (Game.scare), the noise of the player's own trigger (Game.noise,
    once per tic for as long as it is held), and a neighbour running
    past (A_Scare). Measured: a bang forty units away moved a frozen
    shopper ninety units in under two seconds, still solid, still blue,
    with ninety of its hundred frost on. The lock is one line at that
    one door rather than a guard at each caller — the callers were not
    the problem, the NEXT caller was — and the two functions that own
    the ice pass a flag through it. The test knocks on all three doors
    and measures how far the block of ice got: nothing
  A BLOCK OF ICE ROCKING GENTLY ON ITS HEELS, reported by the user and
    a straight miss when the freeze went in. Every standee leans and
    bobs a little — two sines off its own id, which is what stops a
    shop floor of them reading as a room full of cardboard — and the
    freeze parked the state machine without ever touching the drawing.
    So the one figure in the game that has to be dead still was the one
    still swaying. The guard is at the call in Actor.render rather than
    inside swayOf, because swayOf was not wrong: it was asked to sway
    and it swayed. Somebody the fire is eating is held the same way, for
    the same reason — a body coming apart should sag, not sway
  A HALF-BURNT SHOPPER HANGING IN THE AIR, which was the first thing
    wrong with the burn-away on screen and is obvious in hindsight: the
    front eats the drawing from the feet up and the quad does not move,
    so what was left of somebody was a head and a pair of shoulders
    floating at eye level with nothing under them. The sprite sinks at
    the rate the front climbs now, so the unburnt top of them slides
    down to the floor as the bottom goes — which is not a workaround,
    it is the collapse, and it is what makes the three seconds read as
    a person going down rather than as a person being erased
  A SHOPPER ON FIRE THAT LOOKED EXACTLY LIKE A SHOPPER, which is the
    longest-running of these and was never a bug in anything: the code
    was right, the mechanic was right, and nobody had ever drawn the
    fire. Somebody alight was the ordinary sprite with fullbright set,
    and every screenshot of the best thing in the game is a person
    standing near some flames on the floor. Three things now, because
    any one or two of them is not enough: flame licks off the body,
    which trail because they are particles and the person is running; a
    fire colour map on the drawing, without which the licks read as
    somebody standing BEHIND a fire; and the colour being ADDED rather
    than mixed, without which they are the colour of terracotta,
    because every colour in the ember ramp is at most white and a map
    can never make a burning person brighter than a lit one
  AND THEN A COLUMN OF FIRE WITH SOMEBODY LOST INSIDE IT, which was the
    first cut of that: two licks a tic at up to thirty-four units, on a
    person fifty-six units tall, is thirty overlapping blobs each a
    third of their height. One a tic and smaller leaves the drawing
    showing through, which is where the colour map does its work — and
    the point of a burning shopper is that you can see WHO is burning
  A WHITE VAN WITH A RED PINSTRIPE DOWN EVERY EDGE, which is a good
    picture of getting a colour space wrong. The mask that isolates the
    van's white paint is a luminance ramp, and its two numbers were
    measured off the PNG: paint at 0.75 to 0.94, so a ramp from 0.55.
    But the sheet is an sRGB texture and is DECODED on the way out of
    the sampler, so what the shader sees is 0.50 to 0.78 linear — and a
    ramp starting at 0.55 caught the highlights along the panel edges
    and nothing else. Re-measured in linear the bands are miles apart
    (glass 0.28, the darkest shadowed paint 0.53) and the ramp goes
    between them. The test reads the two numbers OUT of the shader and
    applies them to the van's own sheet, decoded the same way, so the
    check and the thing it checks cannot drift
  A CAR PARK OF GREY SHAPES WITH WHEELS, one screenshot later. The
    palette was picked at the values a van is really painted, 0.24 to
    0.6, and this multiplies twice — the sheet's own shading first and
    then a lot at dusk on top of it. Nothing under about 0.4 in its
    strongest channel survives to the screen. The test holds every
    entry against that floor
  A SMOKE TEST THAT COULD NOT REPORT ITS OWN FAILURE. A backtick in a
    comment inside the GLSL ends the template literal early and the game
    dies on IMPORT; the check that would have caught it recorded a
    failure and waited for the summary at the end of the run, which
    never came, because the import that kills the process is a few lines
    further down. It is the first thing the suite does now, reads the
    file as TEXT, and prints and exits on the spot rather than counting
    a failure nobody will ever see
  A PILOT LIGHT HANGING UNDER THE GUN, reported by the user and
    measured at 0.537m off on a gun 1.4 metres long — a fifth of the
    screen's height below the barrel and nearly off the bottom of the
    frame. The two effects on the flamethrower hang off different
    things, and that asymmetry is the whole of it: the muzzle is a
    child of the MODEL and takes its anchor in the model's own units,
    so it is right by construction; the pilot flame cannot be, because
    the model is turned a half circle to point its barrel at the camera
    and a quad that inherits that turn is a flame seen from behind. So
    it hangs off the group instead — and a point handed to `position`
    is read in the PARENT's space, while it was being given a WORLD
    one. The group's own transform, which is the whole of the view
    offset plus the yaw and the bob, was applied to it twice. The tell,
    for anyone who meets this again: the glow the pilot throws ON the
    gun was in the right place the whole time, because that uniform
    takes the same vector in view space and was correct. Only the mesh
    needed converting back out of the world
  A SHADER ENDING IN THE MIDDLE OF A SENTENCE. The GLSL lives in a
    JavaScript template literal, and a pair of backticks in a COMMENT
    inside it closes the string: the file still parsed, and the game
    died on import with "Unexpected identifier". Thirty seconds to
    find, and worth writing down because the prose in that file is
    dense and the temptation to quote an identifier in it is constant
  AND THE SAME BURN RUNNING FROM THE HEAD DOWN, one screenshot earlier.
    vUv.y is measured DOWN the picture — the sprite sheets are
    canvas-backed and arrive with the first row at the top — so the
    obvious spelling of "from the feet up" was upside down. A person
    dissolving from the hat is not a person on fire. The test now pins
    the direction in the shader source, because it is one character and
    nothing else in the game would notice
  A CHARRING CAR AT MINUS INFINITY. The char phase was put in front of
    the launch, and the tic that tipped a burning car over into it —
    burnTic, three lines up in the same function — then fell through
    to the settle code below, which is written for a car that has
    LANDED and integrates its resting angle off numbers a parked car
    does not have. One tic of NaN angles put the lowest corner of the
    box at infinity and the car's middle at minus that, and the first
    spark thrown off it asked the level which sector minus infinity was
    in. The fix is one line — stop after the tic that starts the char —
    and the lesson is the same as the frozen walk-off's: a state added
    to a function written as a run of ifs has to be checked again after
    every call that can change it
  A POLICE VAN PAINTED BLACK. The loader took the first image in a GLB
    for its sheet, and for the van that was the only image. The police
    van carries four — emissive, normal, diffuse, metal-rough — and the
    first is a flat black emissive map, so the whole truck arrived
    matte black with no lettering. A GLB says which picture is the
    colour, in the material's baseColorTexture, and the loader asks it
    now; the test checks that the colour image is NOT the first one in
    the file, so the shortcut cannot come back
  A DEATH ROW WITH ITS FRAMES OUT OF ORDER. The SWAT sheet stacks the
    three lying-down frames in the last column of the death row, and
    grouping the found cells into rows by their vertical middles put
    the second lying frame beside the third falling one, because their
    middles were near enough. So the trooper fell, lay down, knelt up
    again and lay down. That band is cut COLUMNS FIRST now, and the
    order the cut returns is the order the frames play in
  A MEASURING TOOL THAT LIED, for four of its own panels. The new
    flamethrower has no marker spheres, so its nozzle and pilot had to
    be measured off pictures, and the tool drawn to do it took the
    screen's right-hand and up axes as ARGUMENTS: name the camera and
    name what is across the screen. Two of the four views got the
    handedness backwards — a camera looking from +x with +y up has -z
    across the screen, not +z — so the rulers under those panels
    counted the wrong way and the muzzle appeared to be at the tail of
    the gun. The fix is not a better argument: the axes come off the
    camera's own matrix now, so a view cannot disagree with its own
    ruler. Everything a picture is measured against has to be derived
    from the same thing the picture is
  A FLAME THAT WAS NEVER DRAWN, and the gun was blamed for it. The first
    look at the new flamethrower firing showed no plume at the muzzle,
    which read as the bottle on top of the barrel hiding it, and an hour
    went into holding the gun further out, higher and rolled over to get
    round a problem that did not exist. main.js draws the gun with
    weapon3d.update(player, player.firing, ...) and `firing` is
    fireIndex >= 0 — a thing that is true only DURING the fire cycle. The
    probe ticked the world eight times with the trigger down and then
    took the screenshot, by which time the cycle had ended and the muzzle
    quad was hidden, correctly. Parking the cycle open before the shutter
    opens shows the plume exactly where it should be. A screenshot of a
    paused game is a screenshot of whatever state the pause caught
  A LAUNCHER THAT LEFT THE PICTURE. The bore was asked to be a third
    smaller and a third farther off, and the first version of "farther
    off" scaled the gun's whole position along the line from the eye —
    on the theory, which is true, that a point moved along that line
    keeps its place on screen, so the gun would keep its corner of the
    frame and only shrink. The point that kept its place was the gun's
    CENTRE, which sits below the bottom of the frame by design (VIEW.pos
    is low and right so the body is off screen and the barrel comes in
    across the corner), so the launcher shrank around a point nobody
    can see and what was left in the picture was one edge of it. The
    push is straight back along the view now, z alone, which is what
    holding a thing farther from your face is; it recedes toward the
    middle the way anything farther off does, and the whole of the
    launcher's mouth end is in the corner at half its old size. Caught
    by the screenshot, not the test, which can only pin which line the
    push is on: a picture is the one check a scene graph in a stub
    cannot give you
  A PIECE OF CAR ONE PAST THE END OF THE MODEL. rnd() in js/vehicles.js
    is pRandom() / 255 and pRandom() rolls 0 to 255 INCLUSIVE, so it
    returns exactly 1.0 about once in every 256 calls — and the one
    place that used it as an array index, picking which of the van's
    triangles a shed chunk is torn from, then read one past the end and
    threw. Every chunk off every car draws one of these and a chain
    reaction across the car park sheds hundreds, so this was not a rare
    crash, it was a question of how long the player stood and watched.
    It surfaced because an unrelated change moved the shared random
    stream by a few calls and the smoke test's exploding car landed on
    it — which is the argument for a test suite that shares one LCG
    with the game. Clamped at the point of use: the other nine uses of
    rnd() in that file are ranges, where reaching the top is correct
  SMOKE WEARING THE FIRE'S COALS, for as long as there has been soot.
    Every sprite in the game shares the fragment shader with the walls,
    and the block that asks the burn grid how burnt the floor is was
    running for all of them: shoppers stained, giblets stained, and the
    smoke — thirty units up in the air, and drifting, so it sampled a
    different part of the grid every frame and the coals crawled across
    it. Nobody had named it until the user did. A define now, set by
    the wall material and nothing else
  A ROW OF DITHER ONE STEP OUT, every other row, for the whole life of
    the project, and found by accident on the way to something else.
    The post pass ran at SCREEN resolution and worked out its Bayer
    index as floor(uv * bufferSize) — the buffer texel this screen
    pixel is standing on, which is the right quantity and was not
    always the right ANSWER. The hardware's nearest fetch does its own
    floor of the same product in its own arithmetic, and on a 600-row
    window over a 400-row buffer that product lands on a whole number
    every other row; where the two floors fell either side of it, a row
    got its neighbour's threshold. Nobody can see it on a 256-colour
    picture, which is why it lasted. What found it was diffing a frame
    before and after the pipeline was rebuilt: seven per cent of the
    pixels moved, in regular stripes, and with the dither turned off in
    both the two frames came out byte-identical. The filter now works
    the threshold out at grid fragment centres, where it is the same
    number as the fetch by construction
  THE FOUR NUMBERS ALONG THE TOP running off a 160-column grid, which
    had been true since the day there were four of them and only
    became reachable on purpose the day the pixel filter stopped being
    the render size. The bar already stepped its scale down to fit and
    the floor of that is 1, below which it clipped — and what it
    clipped was FUEL, the last one drawn and the one this panel can
    least spare. It gives up a READOUT now once the scale has nowhere
    to go, from the middle out, and the test holds the three lengths
    against the chunkiest grid there is
  and a van painted by projection when it was already unwrapped, on a
    measurement that pooled the body's UVs with the flat material's.
    The flat material has no texture, so its UVs are junk — 490
    triangles "covering" 321 per cent of the sheet — and the junk was
    the fan of slivers the flanks were condemned for. The body's own
    unwrap is 134 triangles over 39 per cent of it. The test measures
    the textured primitive alone, and asserts the other one IS the junk
  and then THE SHEET UPSIDE DOWN on every van in the lot, for a whole
    model, because two flips cancelled and only one of them happened.
    glTF's v starts at the top of the image and GL's t at the bottom,
    so one turn is needed; the code asked for two — `1 - v` on the
    model and `flipY` on the texture — and `flipY` is ignored for an
    ImageBitmap, which is what a texture inside a GLB decodes to. The
    old van hid it, having only 134 textured triangles on a sheet of
    white bodywork; its replacement is unwrapped all over and put a
    radiator grille down the flank of thirty-six vehicles. Nothing in
    564 checks could see it, because every one of them measured the
    UVs and none of them measured which way the picture went on. The
    test pins both halves of the convention now: `flipY` false, and
    the file's own v arriving at the triangles unchanged
  ONE SHOP DOORWAY OUT OF TWENTY that the fire never got through, and
    five rooms behind it that never burned on a map where every other
    room did. A doorway is 120 by 16 — two or three cells of a
    thirty-two-unit grid, in a line — and it is the only way in from the
    footway. At an aisle's fuel a front two cells wide only has to fail
    once, which is the note on the footway's own fuel in its smallest
    possible form, and it did not show up until the parade got long
    enough to have twenty of them. A doorway holds what the pavement
    outside it holds now, which is also true of a real one. The check
    that caught it was already there and phrased correctly: every region
    of the shop must be REACHED, not 97% of the fuel
  a car park with two typed coordinates in it, which was correct until
    the parade grew past them and then described a strip of wood with a
    negative width. The lot is derived from the parade now. The general
    form of this one — a number typed twice, in two files, that has to
    agree — is most of what the checks in tools/smoke-test.mjs are for,
    and three of them were themselves guilty: they asserted the fuel
    grid's bounds and the ends of the road as literal coordinates, and
    they all failed the moment the building changed size. They ask
    structural questions now (is the grid wider than the parade, does
    the road leave the map at both ends) rather than arithmetic ones
  a burn timer that ran at half the speed it said, because the state
    that counts it down runs every TWO tics and the countdown was
    decremented by one. A shopper asked to burn for seven seconds burned
    for fourteen. Nothing errors, nothing looks broken, and the only
    symptom is that every number tuned against it is wrong by a factor
    of two — which it was, through an entire afternoon of tuning. It
    decrements by the frame's own length now: the frame knows how long
    it is, so ask it
  a fatal, silent break. A comment rewritten with a text splice whose end
    offset was one line too far took the function between the two offsets
    with it, and js/main.js was left importing a name js/car.js no longer
    exported. The page died on the first line of module evaluation — no
    textures, no map, no game, a title screen that says STARTING for ever
    — and the test suite passed with 633 green checks, because it imports
    the modules it wants one at a time and never asks whether THEY can
    find each other. There is now a pass that reads every import and
    every export out of the source and holds them against each other
  "the pieces of a person all come down", which stopped being true the
    moment the fire got six times faster: two hundred tics of it beside a
    queue takes the neighbours too, so the count in the air was somebody
    else's pieces and the check was asking the wrong question
  a shop lit by two hundred switched-off light fittings. The ceiling
    texture was drawn as HARDWARE on purpose, with a sprite doing the lit
    part, and the day the sprite came out nothing anywhere said the paint
    was now the only picture of a light in the game — a flat has no
    opinion about whether it is meant to be luminous. The fitting is
    measured against the ceiling tile round it now, and so is the glow it
    throws on that tile, which is the part you actually read
  and the same bug again in the charred half, which is the one that makes
    the point: charring is a filter over pixels, and a darker picture of a
    light is still a picture of a light. A gutted, roofless, black shop
    with four crisp lit panels in every ceiling tile. The dead fitting is
    drawn by hand over the charred ceiling now, and the check demands it
    be darker than the burnt ceiling it is set in rather than merely
    darker than it used to be


WHAT IS NOT DONE
----------------

  the sky is generated and the wood, the people and the gun still
    arrive as files; the sky's stars are a hash and not the Milky Way
    the photograph had, and the band drawn across them is a gesture at
    it. The photograph is still in assets/sky if anyone wants it as a
    star layer under the bake
  nobody lives in the town. No residents, no cars moving, no crowd on
    the streets — two in the morning is the excuse and it is a good one
    for a first pass; it will not survive a second. What the town has
    instead is light in windows, a window that goes dark when its room
    burns, and a hundred vans parked along its kerbs that nobody drives
  the parked vans are all the one van, the car park's, in five colours.
    A town's kerbs want a saloon and a pickup and a station wagon, and
    the fleet has one model
  the houses have no insides. A house is a shell with a facade, and
    its door is painted; the shops on Main Street are the same. The
    first answer — a hall, a stair, two bedrooms behind every door — was
    built, walked by the test and taken out again at the user's request,
    because nobody went in. What is behind a front door is a game design
    question this town does not answer
  a house does not burn. Its yard does, and the siding facing the yard
    chars with it, but a shell with no inside has nothing to hold fire;
    the school and the church are the fuel in the town, and the terrace
    that burnt end to end through its party walls is gone with the
    party walls
  the glass does not break. A pane is a texture in a hole you stop at;
    a round through it leaves no hole and makes no sound
  a lamp does not go out and a headstone does not fall: the stone is a
    sprite with no health and the lamp is geometry with a radius, and
    the lamp's light — the pool's tint and the flare at its head — runs
    on the sky's clock rather than on anything you can shoot
  there are no utility poles down the streets
  a roof does not burn off. A sloped ceiling is a surface the engine
    knows about but not one the fuel grid has a cell for, so a house
    that burns out keeps its roof on. js/ruin.js already drops a deck
    and leaves its steel, and a gable is the obvious next thing to drop
  the church spire is still a DRAWN roof — roofGeometry, four triangles
    over the tower, which is what every roof was before there were
    slopes. A pyramid is four planes and a gable is two
  a burnt-out first floor does not fall into the classroom under it.
    js/ruin.js
    drops a roof and leaves its steel; a storey landing on the one
    below it is the same idea one level down and is the best thing this
    engine could do that no other Doom-alike does
  fire climbs but does not fall: there are up links and no down ones,
    so a fire started upstairs stays there
  the flood is horizontal: an opening you can only see above or below
    the window still lets it through, which draws more than it need
    and never less
  the weather does not change during a night, and nothing in the
    world is wet: no puddle, no wet tarmac, no drip off a canopy. Rain
    falls, damps fuel, and stops
  the sun lights nothing and casts no shadow; dawn is the sky's colour
    and the ambient coming up, and nothing else. Doing better would
    mean normals, and normals would mean this stops being the renderer
    it is
  the clock stops at eight and there is no day: seven keyframes from
    ten at night, and a daytime level is more rows in the same table
    and a different game
  the people, the wood, the sky, the logo and the weapon are the art a
    person made; every other surface in the game is still procedural and
    still provisional
  the shoppers run from fire and from each other going off, and from
    nothing else. They do not get out of your way, they do not use the
    doors, and they do not know the shop — a panicked one takes the
    coolest walkable compass direction that is away from what frightened
    it, which is enough to empty an aisle and is not enough to look like
    somebody leaving a building
  a shopper is drawn from one angle, so a crowd seen from the side is a
    crowd all facing you. At Doom's sprite scale in a dark shop this
    reads; in daylight it would not
  every vehicle in the car park is the same van. It is the user's model
    and it is the only civilian one in the project: about thirty-six of
    them now that the lot is twice as long, sparse, clustered near the
    doors and thinning to almost nothing at the ends, and only the
    heading and the paint differ — no dents, nothing that would break
    the repeat. The six drawn vehicles that used to be measured and
    waiting are deleted with the system that built them; their sheets
    are still in art/ if anybody wants them back. The second GLB did
    drop in beside the van — the police van — and cost eight lines
  the windows are the renderer's, not the game's. The four civilian
    sheets were rendered with see-through glass, so a windscreen shows
    the seats and, past them, the green screen; the tool paints the
    green near-black and leaves the seats. There is no alpha anywhere
    in a vehicle, but the look wants sheets rendered with opaque glass,
    which drop straight in
  a wrecked car never cools past smoking, and never goes away. The
    particles stop after twenty seconds and the coals in the shader do
    not, which is right for the ten minutes anybody plays and would be
    wrong for an hour
  a vehicle in the air ignores everything. It does not hit the building,
    it does not hit another car, and it does not care whose bay it lands
    in — the only thing it collides with is the ground. Two cars going up
    together can end up inside one another, which so far has looked more
    like a pile-up than like a bug
  the police van drives on a polyline and stops for nothing: it does
    not steer round a wreck in the fire lane, it does not slow for a
    crowd, and two of them sent to the same bay would arrive inside one
    another. The bays are taken in order so they do not, and a wreck
    keeps its bay
  four of the six neighbouring units are a shopfront with nothing behind
    it, which is one wall each and buys the whole read of the place
  no music
  no second level, and no level-to-level flow
  the molotov is built and switched off; the boxcutter is deleted
  the cerebral bore's sight is a one-pixel line, which at 300 rows is a
    thick red thread and at 600 a hair; and the bore itself is a
    fourteen-pixel cone that reads as a red blob in flight. Both want
    art
  only the SWAT fight back. The other five tiers in js/responders.js —
    the night manager, security, the police, the fire brigade, the
    helicopter — are still an alarm, a dispatch and a delay with nobody
    at the end of it; the squad has a trigger of its own
  a trooper does not put fires out, does not use a door on purpose (the
    sliders open for anything solid, so he gets in), and walks through a
    burning car park without noticing it, being fireproof. Nothing you
    can pour stops one; the bore is five kills a minute and the curve
    is more than that inside three
  a squad van standing in a fire takes forty-five seconds to go and an
    APC about ninety, which is deliberate and is still a long time to
    stand watching one. What it costs you is a tank; what it buys is a
    bay back. Whether that is a trade anybody makes is not yet known
  the touch controls were proven on an emulated phone — real touch
    events through Chromium, both thumbs at once — and not yet on glass;
    the look speed, the dead zone and the button sizes want a real thumb
    on them, which is what the LOOK SPEED slider is for in the meantime
  the wood, the gun and the particles were proven in software-rendered
    Chromium, which draws them correctly and slowly; fifty-four thousand
    instances at 400 rows is well inside any real GPU, but nobody has
    yet watched it on one
  the player cannot be hurt by fire — asked for, and one flag in
    js/player.js, FIREPROOF. Bullets and vans get through it; nothing
    else does. The tank is finite and fills itself very slowly; nothing
    else refills it, and nothing refills any of the three bars at all.
    There is no armour on the floor to pick up either: what you start
    the night with is what there is of you
  the SWAT sheet and the army sheet are JPEGs, decoded to PNGs in a
    browser and kept in art/people/ as those PNGs, because node has no
    JPEG decoder and one was not worth writing for files converted once
  the army trooper is cut, loadable and proven, and nothing in the game
    spawns one: no actor, no states, and main.js does not fetch the
    strip. Asked for that way — prepared now, built later. THE ORDER IS
    DECIDED: the SWAT, then the army after them, then a SUPER ARMY after
    the army, whose sheet has not arrived. What "after" is measured in
    — the pressure, the clock, the count of the dead — and what brings
    them are not. The SWAT's table in js/states.js is the one to copy
    when the time comes, and the smoke test pins the boundary so that it
    is crossed on purpose
  the gunship's lamp lights nothing. It threw a lit cone into the world
    shader for an afternoon and the user has had the beam out, so the
    searchlight is now a flare and a turret that points at you — which
    is most of what one reads as at night, and is not the pool of light
    on the tarmac that was there for an afternoon
  the flare's occlusion is the aircraft's own hull and the level's
    walls, and nothing else. A van between you and a gunship's lamp
    does not take the flare away, and neither does a tree: the wall
    walk does not know about either of them, and both are small enough
    at the range a gunship is usually at that nobody has minded
  a gunship in the air ignores everything but the ground under it. It
    does not hit the building — it climbs over the parapet rather than
    avoiding it — it does not hit another gunship, and the wreck lands
    wherever it lands, in somebody's bay or on the fire lane
  a hole in a gunship is not drawn. A round into a van leaves one on
    whichever face of its box it came in through; the gunship is a
    tree of parts with no single box, so a round into it makes its
    puff and its sparks and nothing else
  a tracer that has landed within forty-four units of your eye is not
    drawn at all. It never came up while the only thing firing them was
    the gun in your hands, whose rounds fly AWAY at a hundred and fifty
    units a tic; the gunship's come the other way and STOP ON YOU, and a
    streak two and a half units across with its head six units from the
    eye is a quarter of the screen wide. What that costs is the last
    instant of an incoming round, which is the instant you are being hit
    in and not looking at the tracer
  nothing follows you into the wood, and the wood's fire and the
    store's do not cross the car park to each other; the flamethrower is
    the bridge
  the trees are 128 and 256 pixels, the sky 1024, all three guns' paint
    1024, the van's sheet 512x256, the police van's 1024: art that came
    from outside is left as it came unless it is absurd, and the
    64-pixel rule stands for everything the game draws itself. The one
    that was absurd is the gunship, whose 2048-square sheet was six of
    its seven megabytes for a thing usually three hundred units over
    your head; it is halved to 1024 by tools/prep-model.mjs --texture
    1024, and side by side at the range you ever see one, four in a
    thousand pixels of the frame differ at all
  the APC and the three guns are still as they came, at 1024 and 2048.
    The same flag would crunch any of them and nobody has asked: a gun
    is held at arm's length, where a texel IS a centimetre and the
    trade goes the other way
  three of the five models are Vaportrash's, off Sketchfab. The fire
    extinguisher rifle and the cerebral bore are CC-BY-4.0 and want the
    credit above kept wherever the game goes; the flamethrower's own
    extras say COPYRIGHT TO VAPORTRASH and nothing else, which is not a
    licence to ship. Whoever publishes this owes that one either a
    licence from its author or a replacement — the anchors and the prep
    are a table and a tool, so a different model is two numbers and a
    re-run
  no save
