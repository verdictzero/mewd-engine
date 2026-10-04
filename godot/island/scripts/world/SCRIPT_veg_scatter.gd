extends Node3D

# Every plant in the world above ankle height — the firs, the bushes and the
# ferns — scattered from the SAME `IslandField` that paints the ground, so the
# canopy, the undergrowth and the litter under them can never disagree about what
# a patch of ground is. `SCRIPT_grass_scatter.gd` does the ground cover on its own much
# finer grid; this does everything else.
#
# WHAT IT REPLACES. `tree_scatter.gd` stood a 1,264-triangle pine .glb on the
# island and drove a two-level LOD — poly near, runtime-baked impostor far — with
# a dithered cross-dissolve between them. All of that is gone. A plant here is a
# Y-axis billboard of a crunched `sprites/` sprite and nothing else: no poly
# level, no impostor bake, no cross-dissolve band, no `tree_billboard_baker.gd`.
# Two triangles from one metre to the horizon.
#
# That is what pays for the density. The old forest was 6,237 pines on an 11 m
# grid and cost 1.1 million triangles from the ridge — 60% of the frame — because
# the poly level reached 120 m. This one is a ~4 m grid over the whole island,
# every plant a quad, and the whole thing is ten draw calls and a few hundred
# thousand triangles that never change.
#
# ONE GRID, THREE CLASSES, and that is the central decision in the file. The
# obvious construction is a scatter node per class, and it is the wrong one twice
# over: `IslandField.sample` is ~0.15 ms and is the entire cost here, so three
# nodes over the same ground pay for the same ground three times; and three
# independent grids let a fir, a bush and a fern land on the same square metre.
# Instead ONE cell is sampled ONCE and then decides what — if anything — grows in
# it, with the class weighted by `IslandField.forest_at`. See `_evaluate_cell`.
#
# WHAT THE WEIGHTING BUYS, which is the whole brief:
#
#   * FIELDS get grass (`SCRIPT_grass_scatter.gd`) and bushes in clumps, and nothing
#     else. `bush_open_density` is high but it is multiplied by a THRESHOLDED
#     noise, so open ground is mostly bare scrub-wise with occasional thickets
#     rather than uniformly speckled.
#   * WOODS get firs, thick bush thickets and a fern floor, and NO grass — the
#     ground cover stops at the treeline (`grass_scatter.forest_falloff`). The
#     three class weights sum past 1 inside a wood, so every cell of one grows
#     something and the clamp in `_evaluate_cell` decides which.
#   * FERNS ARE FOREST-ONLY (`fern_open_density` 0), so they read as understory,
#     and they are LAST in the priority order, so they fill whatever the trunks
#     and the thickets left.
#
# WHY THE CELLS ARE GROUPED INTO TILES. Same reason as `SCRIPT_grass_scatter.gd` and the
# same measurement that drove it: a per-cell dictionary over this view is tens of
# thousands of entries and a moving camera re-walked all of them. So the unit of
# work is a TILE — `tile_cells` square — meshed once into a finished per-sprite
# instance buffer in render space, and a rescan walks a few hundred tiles and
# memcpys the ones in view.
#
# AND UNDER `prescatter` IT STOPS MESHING ALTOGETHER. The world is bounded, so
# every tile is built behind the loading screen and kept, and once that is done
# the tile SET can no longer change: nothing is ever meshed, pruned or re-meshed
# again, and a scan from the far side of the island dispatches no work at all.
#
# WHAT A SCAN STILL DOES IS CHOOSE, AND THAT IS THE ONE THING IT MUST. Every
# plant on the island used to go into its MultiMesh once and stay there, on the
# argument that a re-pack per scan cell bought only "maybe a third of the quads".
# That argument was measured against ONE fade distance for all three classes —
# 1,300 m, sized for a 22 m fir — and it stops holding the moment the classes get
# their own (see `Distance`). At the shipped bands a fern is gone by 300 m and a
# bush by 820, and the population is nothing like evenly split between the three:
#
#   class     held   band     submitted, standing at the island's centre
#   ferns   316,896  300 m     18,648      94% of them never reach the GPU
#   bushes  135,318  820 m     73,365      46% of them never reach the GPU
#   firs     30,286 1300 m     30,195      the class the long band is for
#   TOTAL   482,500            122,208     965k triangles down to 244k
#
# Measured, not estimated: `tests/PROBE_veg_census.gd` for the held column,
# `tests/TEST_prescatter.gd` for the submitted one. THE FERNS ARE TWO THIRDS OF
# EVERY PLANT IN THE WORLD — `fern_per_cell` is twelve — which is why one band
# sized for a fir was never a compromise between the classes, it was the fir's
# number applied to a population that is mostly not firs.
#
# So the trade reversed: three quarters of the vegetation's triangles stop being
# submitted at all, and what it costs is a re-pack when the camera crosses a
# `scan_cell`. `_fill` fingerprints the tile set it selected per class, so a class
# whose selection did not change does not re-upload — which is the whole cost for
# any class whose fade already reaches past the island, and most frames for the
# ones whose does not.
#
# THE CULL AND THE FADE ARE THE SAME NUMBER, taken from the class's own material
# (`_class_view_sq`), which is what makes this pop-free rather than merely cheap:
# a tile is dropped only once every plant in it is past its material's `far_end`
# and has therefore already been dithered to nothing. Retune the fade and the cull
# follows it; there is no second number to keep in step.

@export var island_world_path: NodePath
## Shader material for the TREES (`MAT_veg_billboard.tres`), and the fallback for
## everything else. Each sprite gets a duplicate carrying its own albedo.
@export var material: ShaderMaterial
## Shader material for the BUSHES (`MAT_veg_understory.tres`). Null falls back to
## `material`, which is what a scene that does not care should do.
##
## IT EXISTS FOR TWO THINGS, and both are the same idea — a knob whose right value
## depends on how big the plant is:
##
##   THE NEAR PROXIMITY FADE, which is a TREE feature and is switched off here.
##     That fade is sized to stop a wood being a wall a metre from the eye, which
##     is a real problem for a 20 m fir and no problem at all for a 3 m bush — and
##     running one clearing radius for both scooped a ten-metre bald circle out of
##     the forest floor that followed the player around, which is the opposite of
##     the dense understory it is standing in. So the trees dither away as you
##     approach and everything shorter than you does not.
##   THE FAR FADE, which is where the frame's triangles went. See `Distance`.
##
## Everything else about the three materials is and should stay identical — same
## shader, same tint, same fog. These are per-layer tunings of two knobs, not a
## second and third look.
@export var understory_material: ShaderMaterial
## Shader material for the FERNS (`MAT_veg_fern.tres`). Null falls back to
## `understory_material` and then to `material`.
##
## A COPY OF THE BUSHES' THAT DIFFERS IN THE FAR FADE ALONE. A fern is the
## smallest thing this scatter plants and by far the most numerous — 316,896 of
## the island's 482,500 plants, because `fern_per_cell` is twelve — so it is the
## class that most wants a short fade and the one that least misses it. See
## `Distance`.
@export var fern_material: ShaderMaterial

@export_group("Sprites")
## The crunched `sprites/` firs. Bake them with `scripts/SCRIPT_crunch_art.gd`.
##
## QUAD ASPECT COMES FROM THE TEXTURE, which is why the crunch pads rather than
## stretches: the quad is `height` metres tall and `height * (tex.x / tex.y)`
## wide, so a sprite whose stored aspect disagreed with its content's would draw
## every instance of that variant squashed. See rule 4 in `SCRIPT_crunch_art.gd`.
@export var tree_sprites: Array[Texture2D] = []
@export var bush_sprites: Array[Texture2D] = []
@export var fern_sprites: Array[Texture2D] = []

@export_group("Placement")
## Logical grid spacing, metres. One candidate plant per cell (jittered), so this
## is the density dial for ALL THREE CLASSES at once — and it is QUADRATIC in
## cost, which is the thing to know before touching it: halving it quadruples the
## cells to field-sample.
##
## At 4 m over the hub that is ~307,000 candidate cells, of which the woods and
## the bush clumps keep something over a third. The sample cost is paid once per
## cell ever; under `prescatter` it is paid entirely behind the loading screen.
##
## In a wood the three class weights sum past 1, so essentially every cell grows
## something and the spacing between FIRS specifically — which take about a third
## of them — is roughly 6.7 m. The understory is finer than the grid because a
## single accepted cell emits a clump of them; see `bush_per_cell`.
@export var veg_grid := 4.0
## Plants avoid ground steeper than this (0 flat .. 1 vertical).
@export_range(0.0, 1.0) var max_slope := 0.35
## Plants stay out of any zone whose grooming influence exceeds this, keeping them
## off fairways, greens, build pads, paths and their aprons.
@export_range(0.0, 1.0) var max_flatten := 0.30
## Plants are sunk this far into the ground, in METRES, so a sprite's soil base is
## buried rather than floating a hair above the surface on a slope. Applied to the
## position rather than to the quad's pivot, so it does not scale with the plant.
## AND BY HOWEVER FAR THE GROUND FALLS AWAY UNDER THE QUAD'S EDGES (at the
## user's request: "make sure tree, bush and grass sprites always intersect the
## ground"): a billboard turns to face the eye, so from some side its bottom edge
## runs straight down the slope, and half its width times the ground's gradient
## is how far a corner would hang in the air. That is added, up to `sink_most`
## of the plant's height, so on a hillside every plant's whole base is in it.
@export var sink := 0.15
## The most a plant is sunk for the slope, as a fraction of its height.
@export var sink_most := 0.3

@export_group("Density")
## Fraction of cells that grow a FIR deep inside a wood, and out on open ground,
## before the clumping noise. The pair is interpolated by `IslandField.forest_at`,
## so a wood is a thicket and the ground between woods carries the odd straggler.
##
## Open is near zero on purpose: `forest_at` is a thresholded noise with a narrow
## edge, so with almost nothing growing outside it, where the woods are and are
## not is exactly the shape of that contour.
## THE THREE PAIRS ARE A PRIORITY, NOT THREE INDEPENDENT PROBABILITIES, once they
## sum past 1 — trees take their share first, bushes take theirs out of what is
## left, ferns fill the remainder. See the clamp in `_evaluate_cell` for why, and
## read the three densities below in that order.
@export_range(0.0, 1.0) var tree_forest_density := 0.55
@export_range(0.0, 1.0) var tree_open_density := 0.02
## How much of the vegetation the crash site's CRATER clears — floor and inner slope
## both, everything inside the lip crest. 1 is bare ground; 0 leaves it wooded. It is
## the skirt OUTSIDE the crest that BURNS rather than clears — see `crater_veg_keep`,
## `crater_veg_band` and `_evaluate_cell`.
@export_range(0.0, 1.0) var crater_clearing := 1.0
## THE LINE BETWEEN THE BARE CRATER AND THE BURNING SKIRT, as a crater weight — 1 on
## the fused floor, `IslandField.crater_rim_paint` (0.45) at the lip crest, 0 out past
## the ash. Ground at or ABOVE this weight is cleared outright; below it the ramp in
## `crater_veg_band` hands the wood back. 0.45 puts the line exactly on the crest.
##
## THE WHOLE INTERIOR GOES, NOT JUST THE BOWL, and that is a correction rather than the
## original intent. The clearing used to START at this weight and ramp to bare by
## `+ 0.35`, which meant plants thinned out gradually going DOWN the inside of the
## crater and did not run out until weight 0.80 — about 61% of the rim radius. What that
## drew was burning ferns and bushes clinging to the crater's inner slope: a wall the
## blast scoured to fused rock, at a slope the same blast is meant to have stripped, with
## a molten floor below it. Half-cleared reads as a fire that spread inward, and nothing
## spread inward here — the hole is where the fuel USED to be. So the ramp now runs the
## other way and finishes at the crest: bare from the crest in, wood from the crest out.
##
## AND IT MOVES THE FIRE WITH IT. `SCRIPT_fire_scatter.gd` copies this at `_ready` and stands a
## fire where a plant would have stood and would be alight, so narrowing the collar to
## the skirt narrows the ring of fires to the skirt too. That coupling is deliberate and
## is the reason the constant lives here and not there: a fire on the inner wall would be
## a fire with no fuel under it.
##
## CLEARED ON THE RAW WEIGHT, NOT `crater_burn`, on purpose: `crater_burn` is already
## pinned at 1 across the entire interior (floor, walls and crest alike all read
## "fully charred"), so it cannot tell a floor a plant should not stand in from a lip
## it should. The raw weight still falls off from the middle, which is the only
## channel that separates the two. What the surviving plants LOOK like is a separate
## question and that one IS `crater_burn` — see `_evaluate_cell`.
@export_range(0.0, 1.0) var crater_veg_keep := 0.45
## How far OUTSIDE `crater_veg_keep`, in crater weight, the clearing takes to let go.
##
## SPENT ON THE SKIRT, which is the point — it is what keeps the crest from being a mown
## line. The weight falls from 0.45 at the crest to 0 by the end of the ash apron, so 0.12
## puts the whole ramp in the first third of the outer drift: about five metres at the
## shipped crater, against `IslandField.crater_wobble`'s 2.75 m of lobing on the radius.
## The wobble being the same order as the ramp is what makes the edge read as a fire front
## rather than as a contour — narrower and the lobes stamp a scalloped circle, wider and
## the ring's inner edge softens into the apron and the collar loses its inside.
@export_range(0.02, 0.5) var crater_veg_band := 0.12
## HOW FAR THROUGH THE FIRE THE WORST-HIT SURVIVOR IS. The ground's char weight
## saturates at 1 across the whole interior, and handing that straight to a PLANT says
## something different from what it says about soil: 1 in `SHADER_veg_billboard.gdshader` is
## not "as burnt as possible", it is FINISHED — every texel swept past the flame band,
## nothing left alight but a residue of coals at `1 - ember_cooling`. A collar of
## plants pinned there is a ring of cold black poles round a crater that is still
## glowing, which is a scar and not a fire.
##
## So the plant's burn is the ground's weight scaled to STOP inside the fire. 0.7
## leaves the worst-hit survivor mostly charred with a live front still in it, and the
## ones further out progressively earlier, so the whole collar is alight rather than
## the outer fringe of it.
##
## AND IT IS WHAT BUYS BACK THE PER-PLANT SPREAD. `burn_of`'s lag term is scaled by
## `amount * (1 - amount)` so that it closes at both ends — which means at exactly 1.0
## it is ZERO and every plant in the band burns in lockstep. That is the flatness, not
## a coincidence: at 0.7 the same term spreads neighbours about +/-0.19, so the band
## holds plants at every stage from vigorously alight to nearly out.
##
## 1.0 restores the old behaviour (a cold black ring). The GROUND is unaffected either
## way — it was charred by the impact and is done, which is why it can sit at 1 while
## the wood standing on it has not finished.
@export_range(0.0, 1.0) var crater_burn_peak := 0.7
## How much of the vegetation the ESCAPE POD'S DIVOT clears. The crater's trio,
## minus the burn — see `_evaluate_cell`.
@export_range(0.0, 1.0) var divot_clearing := 1.0
## The line between bare dent and standing wood, as a divot weight — 1 on the
## floor, `IslandField.divot_rim_paint` (0.40) at the bank crest, 0 past the
## scuff.
##
## SET ON THE CREST, like the crater's, and for a reason that is sharper here.
## The bank is a 2.6 m scarp the pod is leaning on, and the one thing that must
## not happen is a fir growing out of the face it is leaning on: at this size a
## single tree is the same order as the feature and would read as the pod having
## parked in a hedge. Clearing to the crest takes the face and leaves the wood
## standing along the top of it, which is the silhouette the dent wants — a bare
## cut with trees at its lip.
@export_range(0.0, 1.0) var divot_veg_keep := 0.40
## How far outside that, in divot weight, the clearing takes to let go. Wider
## than the crater's 0.12 relative to the feature: the dent's whole paint curve
## spans 20 m against the crash site's 180, so an equally narrow band would be
## about a metre of ground and would cut a line rather than thin a stand.
@export_range(0.02, 0.5) var divot_veg_band := 0.16
## How much of the vegetation the RUIN ENTRANCE's clearing takes out. The divot's
## pair again — a roll per cell, nothing burnt — on `IslandField.ruin_at`'s
## levelling weight: 1 across the flat core, easing to 0 at the edge of the band.
@export_range(0.0, 1.0) var ruin_clearing := 1.0
## The line between the ground the ruin plants and the ground this scatter does,
## as a levelling weight. Every cell sampled at or above it is left to the ruin.
##
## 0.97, WHICH IS THE LEVELLED DISC AND TWO METRES PAST IT — 28.0 m from the ruin's
## axis, the same line as `grass_scatter.ruin_grass_keep`. The disc itself has to be
## left alone because the tile apron is on it and this scatter cannot see a tile; the
## prefab's `GapPlanter` can, and plants the gaps and the ground round the apron out
## to that line with this scatter's own bush art, so the scrub runs unbroken up to
## the stones. The margin past the disc is this grid's, not the plants': the
## understory is emitted in clumps up to 2.55 m from the one point a cell samples,
## so a cell kept at 28.0 m can root a bush at 25.45 m — still clear of the outermost
## stone at 24.67 m, where a cell at the disc's edge would not be.
##
## It was 0.5 (36 m) while the ruin stood in a clearing; see
## `docs/DOC_ruin_gap_growth.md` for why that ring is gone.
@export_range(0.0, 1.0) var ruin_veg_keep := 0.97
## How far below that, in levelling weight, the handover takes — 0.97 down to 0.94
## is 28.0 m to 28.9 m from the axis, so the edge is a thinning rather than a line.
@export_range(0.02, 0.5) var ruin_veg_band := 0.03
## THE WALK UP TO THE RUIN'S DOOR STAYS OPEN: across the clearing's whole footprint,
## no tree, bush or fern stands within this many metres of the line out from the
## door, so the door is never behind scrub from the way it is approached. It is the
## rule the ruin's own bushes keep, at the same width (`RuinGapGrowth.door_clear`,
## held equal by `tests/TEST_ruin_site.gd`), carried on out through the band.
##
## It came free while the clearing ran to 36 m, because the lane was inside it.
## Brought in to 28 m, the scrub put a clump on the line 24 m in front of the door on
## the shipped site, between the door and the pod it faces. Tested per PLANT, not per
## cell, so a clump that straddles the line keeps what stands either side of it.
## Grass is not held off it; the lane is for shrubs, not a mown path. 0 turns it off.
@export_range(0.0, 10.0) var ruin_lane_clear := 2.2
## ...and for BUSHES, which is the density INSIDE A THICKET and not the density of
## the ground generally: both figures are multiplied by a THRESHOLDED clump noise
## (see `bush_clump_lo`/`_hi`), which is zero over most of the map. So a high
## number here does not put bushes everywhere, it makes the clusters solid — in a
## wood it is deliberately set past the room the canopy leaves, so a thicket takes
## every cell the trees did not.
##
## The open figure is what puts clumps of scrub out in the fields, on the same
## thresholded noise, with far more room to fill because almost no trees compete
## for it.
@export_range(0.0, 1.0) var bush_forest_density := 0.75
@export_range(0.0, 1.0) var bush_open_density := 0.55
## ...and for FERNS, the ground-cover layer of the wood. Set high on purpose and
## LAST in the priority order, which together mean "everywhere there is room":
## ferns take every forest cell that is not a trunk and not a thicket, and thin
## themselves out exactly where those are dense without any tuning to say so.
##
## Zero in the open, so a fern is always a sign you are under canopy — the open
## ground has grass for this job (`SCRIPT_grass_scatter.gd`), and grass is the one thing
## that stops at the treeline rather than starting there.
@export_range(0.0, 1.0) var fern_forest_density := 0.80
@export_range(0.0, 1.0) var fern_open_density := 0.0
## Plants emitted per ACCEPTED cell, for the understory classes. This is the
## density dial that is nearly free, and it is worth understanding why before
## reaching for `veg_grid` instead.
##
## The entire cost of placing vegetation is `IslandField.sample`, at ~0.11 ms, and
## it is paid ONCE PER CELL. Halving `veg_grid` to close up the spacing quadruples
## that bill — 4 m to 2.5 m would take the prescatter past the loading screen's
## 90 s guard. Emitting three plants from a cell that has already been sampled
## costs three transforms and NO extra sample, so it buys the same visual density
## for nothing but instance memory and triangles.
##
## What it cannot do is make the ground cover finer than the cell: the extra
## plants are jittered inside their own cell, so they read as a CLUMP at the grid
## scale rather than as an evenly finer lattice. For ferns filling a forest floor
## and for bushes that are supposed to arrive in thickets, a clump is what was
## wanted anyway. Trees are deliberately one per cell — they are 20 m tall and
## three in a 4 m cell would interpenetrate.
##
## The sub-plants share their cell's ONE field sample, so their ground height is
## extrapolated from the sampled normal rather than measured. See `_evaluate_cell`.
##
## FERNS RUN AT FOUR TIMES THE BUSHES because "a fern every 4 m" does not read as
## a fern-covered floor from eye level, and the reason is geometric rather than a
## matter of taste: only about a fifth of any distance ring is inside the camera's
## cone, so the 5-10 m band in front of you holds a couple of visible plants at
## that spacing however evenly they are spread. Closing the mean spacing is what
## makes the near ground look carpeted, and it costs nothing but quads.
##
## THIS IS THE DIAL THAT ACTUALLY MOVES FERN DENSITY, and `fern_forest_density` is
## not. Ferns are last in the priority clamp below, so in a wood their weight is
## almost always pinned by the room the canopy and the thickets leave rather than
## by their own number: at the shipped densities `1.0 - d_tree - d_bush` binds
## first, and raising `fern_forest_density` from 0.80 toward 1.0 changes nothing
## in exactly the cells that matter. Raising the per-cell count multiplies the
## fern population directly and — because it does not touch which cells are
## CHOSEN — leaves the fir and bush counts identically where they were, which is
## the same promise the priority clamp makes and the reason to reach for this
## knob instead.
@export_range(1, 16) var bush_per_cell := 3
@export_range(1, 16) var fern_per_cell := 12
## The bush clump noise is remapped through a smoothstep across this window before
## it multiplies the densities above, which is what turns an even speckle into
## PATCHES. Widen the window for soft-edged drifts of scrub, narrow it for hard-
## edged islands of it; raise both ends for fewer, and lower them for more.
##
## The trees' and ferns' clumping is the plain `0.5 + 0.5 * noise` the old forest
## used, because their patterning already comes from the forest mask.
##
## The noise is a bilinear blend of uniform randoms, so it clusters about 0.5 with
## a spread near 0.19 rather than spanning 0..1 evenly. At the shipped window that
## leaves roughly half of open ground completely bare and about a tenth of it at
## full scrub, which is what "clumps in a field" looks like from the ground.
@export_range(0.0, 1.0) var bush_clump_lo := 0.50
@export_range(0.0, 1.0) var bush_clump_hi := 0.74

@export_group("Size")
## Quad height in METRES, min to max, jittered per instance. Width follows from
## the sprite's own aspect.
##
## These are the QUAD's height, not the plant's: the crunch pads the short axis
## with transparent margin, so a bush occupying 0.74 of its texture's height draws
## at 0.74 of the figure here. `SCRIPT_crunch_art.gd` prints the content fraction of every
## sprite it bakes.
@export var tree_height := Vector2(11.0, 22.0)
@export var bush_height := Vector2(2.2, 4.0)
@export var fern_height := Vector2(1.3, 2.2)
## Extra width jitter, as a multiplier on the aspect-derived width. Independent of
## the height jitter so a stand does not read as one sprite resized.
@export var width_jitter := Vector2(0.88, 1.14)

@export_group("Distance")
## Per-class cull distance in METRES — the range past which a class's plants stop
## being SUBMITTED, as opposed to merely being dithered away. 0 takes it from that
## class's own material, which is what every scene should do and why all three
## ship at 0.
##
## THE FADE AND THE CULL HAVE TO BE ONE NUMBER or the vegetation pops, so by
## default they literally are: `_class_view_sq` reads `far_end` off the material
## the class draws with, and a tile is dropped only once every plant in it is past
## the distance at which the shader has already dithered it to nothing. Retune the
## band on the material and the cull follows. Setting a figure here overrides that
## and takes on the job of keeping the two in step by hand — worth it only to cull
## SHORTER than the fade (a deliberate pop, in exchange for triangles) or to hold
## a class at full range while its fade is being tuned.
##
## WHY THIS IS THE WHOLE PERFORMANCE STORY. One fade for all three classes is one
## fade sized for the tallest of them, and a 22 m fir wants 1,300 m. Under that
## number the ferns — 316,896 plants, two thirds of everything the island grows —
## were submitted across the whole of it every frame to be drawn a pixel and a
## half tall. Splitting the bands takes the world from 482,500 plants submitted to
## ~122,000, i.e. 965k triangles to 244k, without touching a density: the only
## kind of cut that costs nothing where you are actually looking.
##
## Capped at `view_distance`: the streaming path only ever builds tiles inside
## that, so a class asking for more would fade over ground that has nothing on it.
@export var tree_view_distance := 0.0
@export var bush_view_distance := 0.0
@export var fern_view_distance := 0.0
## Sprite buffers `_fill` may re-pack in one scan, with the rest carried to the
## next frame. This is a HITCH dial and nothing else — the same bytes are copied
## either way, over one frame or over three.
##
## The selection is a function of the scan CELL, so a crossing can move tiles
## across all three bands at once and ask for every sprite in the world to be
## re-packed in a single frame. Measured on W2 that is ~5.7 MB and 9.4 ms, against
## a 2.96 ms mean — one visibly long frame per 40 m of travel, which at 120 m/s is
## every third of a second. Spread three at a time it is ~4 ms and the whole set
## refreshes inside three frames, since a scan that leaves work owed forces the
## next one.
##
## WHY IT IS SAFE TO BE LATE. A sprite carried over draws the selection from a
## scan up to a couple of frames old — at 120 m/s, about 7 m of camera travel,
## against a cut that is already conservative by the scan cell's own 44 m and that
## only drops a tile once the shader has finished dithering every plant in it
## away. There is no distance at which a stale-by-7-metres selection shows a plant
## the fade would not have.
##
## A REBASE IGNORES IT ENTIRELY (`_fill_dirty`), and must: there the selection is
## unchanged and it is the BYTES that moved, so a sprite carried to the next frame
## would draw its plants at the old origin — eight kilometres from the island.
@export_range(1, 32) var fill_sprites_per_scan := 3

@export_group("Streaming")
## The outer bound on the whole scatter: no tile is ever built past this, and no
## class may reach past it (see `Distance`). Keep the TREE material's `far_end` at
## or under it, or firs pop out while still fully opaque.
##
## UNDER `prescatter` no tile is ever built or freed at all, so this stops being a
## streaming radius and becomes purely the ceiling on the per-class cull above.
@export var view_distance := 1300.0
@export var keep_margin := 200.0
@export var rescan_interval := 3
## Grid cells per tile side. The tile is the unit of meshing, of caching and of
## visibility. 22 cells is ~88 m at the default grid, matching the tile the old
## forest used.
@export var tile_cells := 22
## Mesh tiles on worker threads, the way `SCRIPT_island_world.gd` meshes its chunks and
## for the same reason: `IslandField.sample` costs about a tenth of a millisecond
## and a tile is `tile_cells` squared of them, which is arithmetic over a field
## clone and has no business on the main thread.
@export var use_threads := true
## Tile meshes allowed in flight at once. The pool is shared with everything else
## that threads, so this is a politeness limit as much as a throughput one.
@export var max_in_flight := 4
## Field samples per scan when `use_threads` is OFF and tiles are meshed inline.
## Spent in whole tiles, so the true ceiling is this rounded up to the next
## `tile_cells` squared. With threads on nothing draws on it: the scan itself
## samples the field zero times.
@export var max_eval_per_scan := 700
## Side of the SCAN CELL, in metres. The eye is quantised to this lattice and a
## scan is skipped entirely while it stays in the same cell. Only the streaming
## path uses it — a prescattered world does no scans at all.
##
## 0 scans every frame the camera moves, which is what the flyover render harness
## wants so its stills are exact. Do not ship it.
@export var scan_cell := 44.0
## The same budget while a loading screen is filling the world in up front.
@export var prefill_eval_per_step := 1200

@export_group("Prescatter")
## Build EVERY tile of every island in range before play starts, and keep them.
##
## This is to the vegetation what `island_world.prewarm` is to the terrain, and it
## replaces the ordinary prefill rather than adding to it. Afterwards nothing is
## ever MESHED again: `_prune_tiles` is disabled, no scan dispatches a worker, and
## every tile of the world is held for the rest of the session.
##
## It does not follow that every tile is DRAWN. A scan still runs and still chooses
## which of the held tiles each class submits, against that class's own fade — see
## `Distance`, which is where the frame's triangles actually go.
##
## ONLY FOR A BOUNDED WORLD — an endless field has no such number, and this would
## try to enumerate it. `tests/PROBE_veg_census.gd` counts what it costs on the
## shipped field before you pay for it.
@export var prescatter := false
## Metres around the anchor within which islands are prescattered. 0 takes the
## `IslandWorld`'s own `view_distance`, so the vegetation covers exactly the
## terrain that was built for it and no more.
##
## Islands are taken WHOLE: an island whose centre is in range is scattered to its
## full extent, because half a wood with a straight edge down the middle of it is
## worse than either building the rest or building none of it.
@export var prescatter_radius := 0.0
## Tile builds in flight while prescattering, or 0 to take one per core less one.
##
## THIS USED TO BE A CONSTANT 4, on a measurement that was not measuring what it
## said it was. `PROBE_scatter_threads.gd` reported "no scaling past four workers"
## and the export was pinned there — but the tiles were dispatched at LOW worker
## priority, and Godot caps concurrent low-priority tasks at
## `threading/worker_pool/low_priority_thread_ratio` (0.3) of the pool. On a
## four-core box that ratio resolves to ONE thread, so every width from 1 to 16
## measured the same single worker and the flat line was read as a scaling cliff.
## `tests/PROBE_scatter_threads.gd --priority=high` shows the difference: 3.0 s at
## one lane against 1.7 s at three, on the same 48 tiles.
##
## So the prescatter now runs on HIGH-priority lanes, like `island_world`'s
## prewarm has all along (`_pregen_staff_lanes`), and takes its width from the
## core count the same way. One below it: the main thread still has installs and a
## loading screen to draw.
##
## IT IS ONLY THIS WIDE WHILE SOMETHING IS COVERING THE SCREEN. See
## `_prescatter_width` — once the player can see the world, the build drops to a
## single lane on purpose.
@export var prescatter_in_flight := 0

# Godot's 3D MultiMesh instance stride: the transform as three rows of four (12),
# plus one custom-data vec4 (16). The custom vec4's .x carries this plant's crater
# burn into `SHADER_veg_billboard.gdshader` (`INSTANCE_CUSTOM.x`) so a ring of forest can
# burn around a crash site while the rest of the island stays green — a per-INSTANCE
# quantity the shared, per-sprite material cannot hold. .yzw are unwritten (0) and
# reserved. There is no per-instance colour: the ground tint the grass used to carry
# is gone with the lit shader that consumed it.
const _STRIDE := 16
# Offset of the custom-data vec4 within the stride — straight after the 12 transform
# floats, matching `MultiMesh.use_custom_data` for TRANSFORM_3D.
const _CUSTOM_OFF := 12

# Class ids, and the order the sprite table is laid out in.
const CLS_TREE := 0
const CLS_BUSH := 1
const CLS_FERN := 2

var _world: Node3D = null
var _field: IslandField = null
var _origin_offset := Vector3.ZERO
var _frame := 0
var _force_rescan := false
# The scan cell the last scan was taken from, and whether there has been one.
# Quantised in all THREE axes: the visibility cut is on true 3D distance, so a
# camera climbing changes what is in view just as surely as one walking.
var _last_cell := Vector3i.ZERO
var _have_cell := false
# The LOGICAL eye the last scan was taken from, which is the one thing a rebase
# does not change — the world moves under the camera, not the camera through it.
# `_refill_static` re-selects around this rather than reading the camera back,
# because the camera's own shift and this node's are two independent visits by
# `floating_origin` in no defined order: half the time `cam.global_position` has
# already been rebased and half the time it has not, and the difference is eight
# kilometres, which is the whole island's vegetation.
var _eye := Vector3.ZERO
var _have_eye := false
var _prune_tick := 0
var _tile_size := 88.0

# The prescatter work list and how far through it we are, plus the flag the rest
# of the file branches on: `_prescattered` means every tile in the world is built
# and KEPT — nothing is meshed, probed, pruned or re-meshed for the rest of the
# session. It does NOT mean the MultiMeshes are frozen; a scan still chooses which
# of those tiles each class submits (see `_fill`).
var _pre_queue: Array = []
var _pre_cursor := 0
var _pre_owed := 0
var _pre_ready := false
var _prescattered := false
## Tiles collected off the lanes so far. The completion test counts INSTALLS
## rather than the cursor, so a lane that has claimed a tile but not finished it
## still shows as owed.
var _pre_installed := 0
## Lanes running, and how many are wanted. Both read by the lanes themselves to
## decide whether to retire, so both are guarded by `_pre_mutex` — which also
## guards `_pre_cursor`, the shared claim, and `_origin_offset`, which a lane
## reads once per tile and a rebase writes from the main thread.
var _pre_live := 0
var _pre_width := 0
var _pre_mutex := Mutex.new()
## Lanes run on THREADS OF THEIR OWN rather than on `WorkerThreadPool` — see
## `SCRIPT_build_lanes.gd`, which is entirely about why, and note that the
## terrain prewarm this build shares a machine with does the same.
var _pre_lanes := BuildLanes.new("veg prescatter lane")
## The last frame `prefill_step()` was called on — i.e. the last frame something
## was holding a screen up in front of the world. See `_prescatter_covered`.
var _pre_step_frame := -1
## Tiles the `VegBake` store already holds, split out of `_pre_queue` at setup so
## the lanes never see them. Drained on the main thread a batch per step — see
## `_prescatter_take_baked`.
##
## Consumed through a CURSOR rather than by shrinking, so that
## `_pre_queue.size() + _pre_baked.size()` is a fixed total for the whole build.
## `_pre_owed` is that total less what has landed, and a list that shrank as it
## drained would subtract the same tiles twice and drive the bar backwards.
var _pre_baked: Array = []
var _pre_baked_next := 0
## The `VegBake` autoload, or null when there is none.
##
## RESOLVED BY PATH AND HELD UNTYPED, rather than named. Naming an autoload is a
## COMPILE-TIME reference, and `tests/TEST_island_world.gd` PRELOADS this file to
## read its exports — a preload compiles it before autoloads have registered, so a
## named `VegBake` fails the whole script and every harness that touches it gets a
## GDScript with no `new()`. `SCRIPT_world_loading_screen.gd:_pick_font` hit the
## same wall and says more about it. Untyped because the calls are then dynamic,
## which is what makes a null one a no-op the branches below can guard rather than
## a parse error.
var _bake = null
## Whether this scatter opened the store and may therefore read and fill it. False
## when `prescatter` is off (see the store's header for why an unbounded world is
## not welcome in it), and when there is no autoload to open.
var _bake_open := false

# Logical tile (Vector2i, `_tile_size` metres square) -> record, in two shapes:
#
#   {"y0", "y1"}                     probed only: the height band the ground
#                                    occupies here, enough to place the tile in
#                                    space and decide whether it is worth meshing
#   {"y0", "y1", "bufs", "n"}        meshed: one finished PackedFloat32Array per
#                                    sprite variant, in RENDER space, and the
#                                    plant count they share
#
# `bufs` is what tells the two apart, and its presence means the tile is done.
var _tiles := {}
var _box_min := Vector2i.ZERO
var _box_max := Vector2i.ZERO
var _box_valid := false
# Tiles in view still wanting a probe, a mesh, or a worker to finish, as of the
# last scan. The scan recomputes it every time; `prefill_ratio` reports against
# its high-water mark.
var _todo := 0
var _prefill_total := 0

# Tile -> WorkerThreadPool task id (-1 when meshed inline), and the results those
# workers have finished with. Same shape as `SCRIPT_island_world.gd`'s chunk dispatch.
var _pending := {}
var _done: Array = []
var _done_mutex := Mutex.new()
# Prepared `IslandField` clones, one per worker that wants one at a time. Cloning
# is the expensive part, so they are handed back rather than dropped.
var _field_pool: Array = []
var _pool_mutex := Mutex.new()

# One MultiMesh per sprite, flattened across the three classes in CLS_ order.
var _meshes: Array[MultiMesh] = []
var _instances: Array[MultiMeshInstance3D] = []
# Class -> [first sprite index, count), so `_evaluate_cell` can roll a variant
# inside its own class and still return one flat index.
var _class_span: Array[Vector2i] = []
# Class -> quad height range, indexed the same way.
var _class_height: Array[Vector2] = []
# Flat sprite index -> its quad's width over its height, so `_evaluate_cell`
# knows how far a plant's quad reaches either side of its base (see `sink`).
var _sprite_aspect := PackedFloat32Array()
## AND HOW MUCH OF EACH SPRITE'S BOTTOM IS EMPTY (at the user's request:
## "trees and bush sprites need to intersect the ground"): the candy
## sprites carry a band of clear pixels under the plant — a tenth to a
## fifth of the picture — so a quad whose base is on the ground stands
## its plant that much in the air. Read off the picture once
## (`_bottom_pad`), and the plant is sunk that share of its height on
## top of `sink`, so the drawn plant's own foot is in the ground.
var _sprite_pad := PackedFloat32Array()

## The share of a sprite's height that is clear under the plant.
static func _bottom_pad(tex: Texture2D) -> float:
	if tex == null:
		return 0.0
	var img: Image = tex.get_image()
	if img == null or img.is_empty():
		return 0.0
	if img.is_compressed():
		img = img.duplicate()
		img.decompress()
	var used := img.get_used_rect()
	if used.size.y <= 0:
		return 0.0
	return clampf(float(img.get_height() - used.end.y) / float(img.get_height()), 0.0, 0.5)
# Class -> SQUARED cull distance, resolved once in `_build_multimeshes` from the
# `Distance` exports and, where those are 0, from the class material's own
# `far_end`. This is what makes the cull and the fade the same number.
var _class_view_sq := PackedFloat32Array()
# Class -> a fingerprint of the tile set `_fill` last selected for it, so a class
# whose selection did not change this scan does not re-upload. -1 is "never
# filled"; `_fill_dirty` forces all three past it when the BUFFERS changed under a
# selection that did not (a tile landing, a rebase).
var _fill_fp := PackedInt64Array()
var _fill_dirty := true
# Sprite -> 1 while its MultiMesh is out of date with the selection its class last
# agreed on. `_fill` clears at most `fill_sprites_per_scan` of them per scan and
# forces another scan while any are left; see that export for why being a frame or
# two late is invisible and where it would not be.
var _fill_owed := PackedByteArray()
var _ready_ok := false


func _ready() -> void:
	add_to_group("origin_shiftable")
	_world = get_node_or_null(island_world_path) as Node3D
	if _world != null and _world.has_method("get_field"):
		_field = _world.get_field()
	if _field == null:
		push_warning("veg_scatter: no IslandField (set island_world_path). Disabled.")
		return
	# START IN STEP WITH THE WORLD. This scatter tracks its own copy of the
	# logical/rendered offset and moves it on every rebase, which was complete
	# while the two frames could only ever start out equal. `TerrainWorld` can now
	# be authored with a non-zero `logical_origin` — SCENE_test_zone_Q2 uses it to
	# put an airfield under the spawn — and a scatter that assumed zero would
	# sample the field 8.4 km from where it plants things: wrong heights, wrong
	# forest mask, and no idea that the ground under the runway is groomed.
	if _world != null and _world.has_method("origin_offset"):
		_origin_offset = _world.origin_offset()

	if not _field._ready:
		_field.prepare()
	if material == null:
		push_warning("veg_scatter: no material assigned. Disabled.")
		return
	_tile_size = maxf(veg_grid, 0.01) * float(maxi(tile_cells, 1))
	_build_multimeshes()
	_ready_ok = not _meshes.is_empty()
	if _ready_ok and prescatter:
		# AFTER `_build_multimeshes`, not before: a tile's buffers are indexed by
		# flat sprite index, so the store's signature has to be taken against the
		# sprite layout the tiles will actually be packed for. Opened here rather
		# than at the first prescatter step so a store that does not match is
		# emptied before anything can read it.
		#
		# `open` adopts a store built from the same field, the same exports and the
		# same placement code, and throws away one that was not — so coming back
		# from a battle starts full and changing a density starts empty.
		_bake = get_tree().root.get_node_or_null("VegBake")
		if _bake != null:
			# From memory when the last scene left a store there, from a file
			# `TOOL_bake_world.gd` wrote when it did not, and from nothing when
			# the world has genuinely changed.
			_bake.open_with_disk(_bake.STORE_NAME,
					_bake.signature_of(_field, self))
			_bake_open = true


# One MultiMesh per sprite across all three classes, laid out tree-bush-fern so a
# flat sprite index is enough to address any of them.
#
# Each gets its own DUPLICATE of the shared material so it can carry its own
# albedo — duplicating rather than reusing matters, since a ShaderMaterial
# assigned to two instances is one object and the second assignment would silently
# repaint the first.
func _build_multimeshes() -> void:
	_class_span.resize(3)
	_class_height.resize(3)
	_sprite_aspect.clear()
	_sprite_pad.clear()
	_class_view_sq.resize(3)
	_fill_fp.resize(3)
	var sets := [tree_sprites, bush_sprites, fern_sprites]
	var heights := [tree_height, bush_height, fern_height]
	var names := ["Tree", "Bush", "Fern"]
	# Trees take `material`; the bushes and the ferns each take their own when the
	# scene wired one up, and fall back inward when it did not. See those exports
	# for the two numbers the three differ on.
	var under: ShaderMaterial = understory_material if understory_material != null \
			else material
	var fern: ShaderMaterial = fern_material if fern_material != null else under
	var mats := [material, under, fern]
	var views := [tree_view_distance, bush_view_distance, fern_view_distance]
	for cls in range(3):
		_fill_fp[cls] = -1
		_class_view_sq[cls] = _resolve_view(float(views[cls]),
				mats[cls] as ShaderMaterial)
		var first := _meshes.size()
		for i in range((sets[cls] as Array).size()):
			var tex: Texture2D = (sets[cls] as Array)[i]
			if tex == null:
				continue
			# The quad is ONE METRE TALL and as wide as the sprite's aspect, so the
			# per-instance scale below is a height in metres directly and the two
			# jitters stay independent of each other.
			var sz := tex.get_size()
			var quad := QuadMesh.new()
			quad.size = Vector2(sz.x / maxf(sz.y, 1.0), 1.0)
			# The pivot is the plant's BASE, not its middle: the scatter places it
			# on the ground, and a centre-pivoted quad would bury half of it. The
			# sink is applied to the POSITION instead, so it stays a fixed number of
			# metres however tall the plant is.
			quad.center_offset = Vector3(0.0, 0.5, 0.0)

			var mat: ShaderMaterial = (mats[cls] as ShaderMaterial).duplicate()
			mat.set_shader_parameter("albedo_tex", tex)
			# (the quad's size in the instance's metres, for the lo-fi texel
			# grid: SHADER_veg_billboard `lofi_texels_per_m`)
			mat.set_shader_parameter("quad_size", quad.size)
			# And the burn map that goes with it, found by name beside the sprite —
			# see `VegBurn.bind_map`. The duplicate is the only place this can be set:
			# the map is per-SPRITE and the shared material is per-class.
			VegBurn.bind_map(mat, tex)

			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			# Per-plant crater burn rides in the custom-data vec4 — see `_STRIDE` and
			# `_pack_tile`. On every plant off a crash site it is 0, which the shader
			# reads as "follow the bus", so this costs the ordinary island nothing but
			# four floats an instance it never has to look at.
			mm.use_custom_data = true
			mm.mesh = quad

			var inst := MultiMeshInstance3D.new()
			inst.name = "%s%d" % [names[cls], i]
			inst.multimesh = mm
			inst.material_override = mat
			# Vegetation shadows would be a hundred thousand alpha-scissored quads
			# in the shadow pass, and the plants are unlit anyway — a shadow cast by
			# something that does not respond to the light that casts it is a lie
			# the eye picks up immediately.
			inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(inst)

			_meshes.append(mm)
			_sprite_aspect.append(quad.size.x)
			_sprite_pad.append(_bottom_pad(tex))
			_instances.append(inst)
		_class_span[cls] = Vector2i(first, _meshes.size() - first)
		_class_height[cls] = heights[cls]
	_fill_owed.resize(_meshes.size())
	_fill_owed.fill(0)


# One class's cull distance, SQUARED and ready for `_fill` to compare a tile's box
# distance against.
#
# `override` is the class's `Distance` export and wins when it is set. Otherwise
# the figure comes off the material the class actually draws with, which is the
# entire point: the shader has already dithered a plant to nothing by `far_end`,
# so dropping the tile at exactly that distance is invisible by construction and
# stays invisible when someone retunes the band without reading this file.
#
# A material that never sets `far_end` reports null (the shader's own default is
# not visible from here), and a class with no material at all is possible in a
# scene that only wired up one. Both fall back to `view_distance`, which is the
# behaviour the whole scatter had before the bands were split — i.e. the safe
# direction to fail in: too much submitted, never a hole.
func _resolve_view(override: float, mat: ShaderMaterial) -> float:
	var d := override
	if d <= 0.0 and mat != null:
		var f = mat.get_shader_parameter("far_end")
		if f != null:
			d = float(f)
	if d <= 0.0:
		d = view_distance
	# No class may outrun the streamer that builds its tiles.
	d = minf(d, view_distance)
	return d * d


# Rebase. The tile buffers hold RENDER-space transforms, so they are patched in
# place — three floats per instance — rather than thrown away: rebuilding them
# would re-sample the field for the whole island, in the single frame the world
# jumps eight kilometres.
func apply_origin_shift(shift: Vector3) -> void:
	# Under `_pre_mutex` because a prescatter lane reads this once per tile to pack
	# against, and a torn read would put a tile's worth of plants at neither
	# origin. A tile packed against the PREVIOUS one is fine and already handled —
	# `_install_tile` compares `r["off"]` and patches the drift — so the lock is
	# only buying a coherent value, not a synchronised one.
	_pre_mutex.lock()
	_origin_offset -= shift
	_pre_mutex.unlock()
	for key in _tiles:
		var rec: Dictionary = _tiles[key]
		if rec.has("bufs"):
			_shift_bufs(rec["bufs"], shift)
	# Every MultiMesh is a CONCATENATION of the tile buffers just patched, not a
	# view onto them, so they do not follow. The selection did not change — the
	# camera is where it was, the world moved under it — so `_fill`'s fingerprints
	# would skip all three classes and leave the whole island eight kilometres away
	# with nothing left to notice. `_fill_dirty` is what says "same choice, new
	# bytes".
	_fill_dirty = true
	# A prescattered world does not otherwise scan on its own schedule, so the
	# rebuild has to happen HERE rather than being left to the next scan: one frame
	# of the island at its old origin is one frame of the vegetation across the map
	# from the ground it grows on.
	if _prescattered:
		_refill_static()
	_force_rescan = true


# Add `shift` to the origin of every instance in every buffer. The origin sits at
# offsets 3, 7 and 11 of the stride — see `_pack_tile` for the layout.
func _shift_bufs(bufs: Array, shift: Vector3) -> void:
	for i in range(bufs.size()):
		var b: PackedFloat32Array = bufs[i]
		var k := 3
		while k < b.size():
			b[k] += shift.x
			b[k + 4] += shift.y
			b[k + 8] += shift.z
			k += _STRIDE
		bufs[i] = b


func _process(_delta: float) -> void:
	if not _ready_ok:
		return
	# A prescatter owns the tile table until it is finished. Letting the ordinary
	# scan run alongside it is not merely redundant, it actively undoes the work:
	# it competes for the same worker slots with tiles the prescatter is already
	# queueing, and its `_prune_tiles` drops everything outside the view — which,
	# while the world is being built from a spawn point near one shore, is most of
	# the island.
	#
	# AND IT STEPS ITSELF, which is a correctness requirement rather than a belt on
	# top of braces. The upload is ALL OR NOTHING while the build is running:
	# `_install_tile` only files a tile's buffers in `_tiles`, and the lone
	# `_refill_static()` on the last line of `_prescatter_step` is the first thing
	# that ever reaches a MultiMesh. Stop the stepping one tile short and every
	# MultiMesh stays at instance_count 0 — not a thinner wood, NO wood, and no
	# error to say so.
	#
	# `SCRIPT_world_loading_screen.gd` used to be the only caller, and it stops calling on
	# a WALL CLOCK (`scatter_timeout`) and then `set_process(false)`s itself for
	# good. So the whole island's vegetation hung on the build beating a stopwatch
	# it knew nothing about: overrun it by one frame and the world was bald for the
	# rest of the session. tests/RENDER_w2_ground.gd hit the same edge from the
	# other side by deleting the screen outright (3460a07) and papered over it in
	# the harness; this is the same bug in the shipping path.
	#
	# The screen's `prefill_step()` calls still land and still do the bulk of the
	# work behind the bar. They are now an accelerator, not the reason it finishes.
	#
	# WHAT IT COSTS TO CARRY ON WITHOUT THE SCREEN is the other half, and finishing
	# is only half of getting that right. A build that keeps every lane busy after
	# the bar has gone hands the player a bald island at a fraction of the frame
	# rate, which snaps back the moment the last tile lands — the exact shape of
	# "the vegetation drops my FPS and then it recovers". So the width is not a
	# constant: see `_prescatter_width`, which reads three lanes behind the screen
	# and one in front of it. `tests/PROBE_veg_timeline.gd --expose` measures the
	# uncovered build end to end.
	if prescatter and not _prescattered:
		_prescatter_step()
		return
	# ONCE IT IS FINISHED THE PRESCATTERED WORLD FALLS STRAIGHT THROUGH TO THE
	# ORDINARY SCAN, and that is cheap there by construction rather than by a special
	# case. Every tile it walks is already meshed, so it dispatches no worker
	# (`_prescattered` skips both `todo` branches), frees nothing (`_prune_tiles`
	# guards itself) and — unless the camera has crossed a `scan_cell` AND that
	# crossing moved a tile across some class's fade — uploads nothing either
	# (`_fill`'s fingerprints). What is left of it is the SELECTION, which is what
	# keeps a fern from being submitted from a kilometre away to be drawn a pixel
	# and a half tall.
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	_frame += 1
	if not _force_rescan and _frame % maxi(rescan_interval, 1) != 0:
		return
	var eye := cam.global_position + _origin_offset   # logical
	# Everything a scan produces is a function of the CELL, so an eye still inside
	# the one the last scan was taken from would recompute an identical answer.
	# `_pending` is in the test as well as `_force_rescan`: a worker whose tile has
	# drifted out of the scanned box stops being counted in `_todo`, and without
	# this its result would sit in `_done` unclaimed while the camera is parked.
	var cell := _scan_cell(eye)
	if scan_cell > 0.0 and not _force_rescan and _have_cell \
			and cell == _last_cell and _pending.is_empty():
		return
	_force_rescan = false
	_have_cell = true
	_last_cell = cell
	_rescan(eye)


func _rescan(eye: Vector3, budget := -1) -> void:
	_eye = eye
	_have_eye = true
	var view_sq := view_distance * view_distance
	# The scan cell's own box. Every distance below is measured from THIS, not from
	# `eye`, so the whole scan is a function of the cell and stays correct wherever
	# in the cell the camera drifts before the next one. At `scan_cell` 0 the box
	# collapses onto the eye and every test below reduces to the point test it
	# replaced.
	var lo := eye
	var hi := eye
	if scan_cell > 0.0:
		lo = Vector3(_scan_cell(eye)) * scan_cell
		hi = lo + Vector3(scan_cell, scan_cell, scan_cell)
	var tmin := Vector2i(floori((lo.x - view_distance) / _tile_size),
			floori((lo.z - view_distance) / _tile_size))
	var tmax := Vector2i(floori((hi.x + view_distance) / _tile_size),
			floori((hi.z + view_distance) / _tile_size))

	# --- walk the box, touching no field ---------------------------------------
	# NOT ONE FIELD SAMPLE HAPPENS HERE. A tile nothing is known about is judged on
	# its FLAT footprint distance, which is arithmetic on its key: true 3D distance
	# is never less than that, so a tile whose footprint is already out of range
	# cannot be in view whatever its height turns out to be. Everything past that
	# — the height probe included — belongs to the worker.
	#
	# THE VISIBLE SET IS COLLECTED IN THE SAME PASS. The walk already visits every
	# tile that can be in view and already has its distance in hand, so classifying
	# it costs a branch; a second pass over the tile DICTIONARY instead would be
	# sized by how much ground has been visited rather than by how much is in view.
	#
	# The entry carries the DISTANCE and the KEY alongside the buffers, because the
	# per-class cut in `_fill` needs both: the distance is what each class tests
	# against its own fade, and the key is what its fingerprint is built from. Both
	# are already in hand here and neither is recoverable from `bufs`.
	_collect_done()
	var todo: Array = []
	var in_flight := 0
	var visible: Array = []
	for tz in range(tmin.y, tmax.y + 1):
		for tx in range(tmin.x, tmax.x + 1):
			var key := Vector2i(tx, tz)
			if _pending.has(key):
				in_flight += 1
				continue
			var rec = _tiles.get(key, null)
			if rec == null:
				# A PRESCATTERED world is closed: the enumeration already decided
				# which tiles can hold a plant, so a key that is not in the table is
				# void and asking a worker about it would only confirm that — every
				# time the camera came within reach of the same stretch of shore.
				if _prescattered:
					continue
				var fd := _flat_dist_sq(key, lo, hi)
				if fd <= view_sq:
					todo.append([fd, key])
				continue
			var d := _tile_dist_sq(key, rec, lo, hi)
			if rec.has("bufs"):
				if d <= view_sq and int(rec["n"]) > 0:
					visible.append([d, rec["bufs"], _key_hash(key)])
				continue
			# Probed but not meshed: the camera was too high, or too far, when the
			# worker looked. Now it knows the tile's real height band.
			if d <= view_sq and not _prescattered:
				todo.append([d, key])
	_box_min = tmin
	_box_max = tmax
	_box_valid = true

	# --- hand the nearest of them to a worker ----------------------------------
	var cap := maxi(max_eval_per_scan if budget < 0 else budget, 1)
	var per := maxi(tile_cells, 1) * maxi(tile_cells, 1)
	var spent := 0
	var left := in_flight
	if not todo.is_empty():
		todo.sort_custom(func(a, b): return a[0] < b[0])
		for i in range(todo.size()):
			var key: Vector2i = todo[i][1]
			if use_threads:
				if _pending.size() >= maxi(max_in_flight, 1):
					left += todo.size() - i
					break
				_pending[key] = WorkerThreadPool.add_task(
						_tile_task.bind(key, _origin_offset, lo, hi, false), false,
						"veg tile %d,%d" % [key.x, key.y])
				left += 1
			else:
				if spent >= cap:
					left += todo.size() - i
					break
				_install_tile(_tile_work(key, _field, _origin_offset, lo, hi, false))
				spent += per
	_todo = left
	if left > 0:
		# Keep going next frame past the scan-cell gate, so a parked camera still
		# fills its neighbourhood in.
		_force_rescan = true

	_fill(visible)
	_update_bounds(lo - _origin_offset, hi - _origin_offset)   # render space

	# A prescattered world is complete by construction and nothing may be dropped
	# out of it: an eviction here would be a hole in a wood that has no machinery
	# left to notice or refill it.
	if not _prescattered:
		_prune_tick += 1
		if _prune_tick >= 8:
			_prune_tick = 0
			_prune_tiles()


# Place a tile in space without meshing it: the field's height at its four corners
# and its centre, widened by half a tile for whatever the ground does between
# them. Five samples against the `tile_cells` squared a mesh costs, which is what
# lets a worker dismiss a tile the camera is too high above without meshing it.
#
# The corners matter, not just the centre. This island has cliffs a hundred metres
# tall, and a tile straddling one has ground at the camera's feet AND ground far
# below; a centre probe alone would put the whole tile at one of those heights and
# could dismiss it while the player stands on it.
func _probe_tile(key: Vector2i, f: IslandField) -> Vector2:
	var x0 := float(key.x) * _tile_size
	var z0 := float(key.y) * _tile_size
	var lo := INF
	var hi := -INF
	for p in [Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(0.0, 1.0),
			Vector2(1.0, 1.0), Vector2(0.5, 0.5)]:
		var h := float(f.sample(x0 + p.x * _tile_size,
				z0 + p.y * _tile_size).get("height", 0.0))
		lo = minf(lo, h)
		hi = maxf(hi, h)
	var slack := _tile_size * 0.5
	return Vector2(lo - slack, hi + slack)


# The lattice cell an eye falls in. Only meaningful when `scan_cell` > 0; the gate
# in `_process` checks that before comparing.
func _scan_cell(eye: Vector3) -> Vector3i:
	var q := maxf(scan_cell, 0.001)
	return Vector3i(floori(eye.x / q), floori(eye.y / q), floori(eye.z / q))


# Squared 3D distance between a tile's BOX — its logical footprint by its height
# band — and the SCAN CELL's box. Zero where they overlap, so a camera standing on
# a tile always matches it.
#
# TRUE 3D, deliberately, matching what the shader's fades are measured on. Gating
# on flat XZ distance instead would let plants directly under a high camera be
# faded out by the material while still being classified in view.
#
# Box to box rather than box to point, and that is the whole quantisation: the
# answer is then valid for every eye position the cell contains, which is exactly
# the set of positions that will be skipped before the next scan.
func _tile_dist_sq(key: Vector2i, rec: Dictionary, lo: Vector3, hi: Vector3) -> float:
	return _band_dist_sq(key, float(rec["y0"]), float(rec["y1"]), lo, hi)


func _band_dist_sq(key: Vector2i, y0: float, y1: float, lo: Vector3,
		hi: Vector3) -> float:
	var dy := maxf(maxf(y0 - hi.y, lo.y - y1), 0.0)
	return _flat_dist_sq(key, lo, hi) + dy * dy


# The same thing with the height thrown away — a lower bound on the 3D distance
# that costs no field sample, so it can be applied to a tile nothing is known
# about yet.
func _flat_dist_sq(key: Vector2i, lo: Vector3, hi: Vector3) -> float:
	var x0 := float(key.x) * _tile_size
	var z0 := float(key.y) * _tile_size
	var dx := maxf(maxf(x0 - hi.x, lo.x - x0 - _tile_size), 0.0)
	var dz := maxf(maxf(z0 - hi.z, lo.z - z0 - _tile_size), 0.0)
	return dx * dx + dz * dz


# ------------------------------------------------------------ worker payload

# Borrow a prepared field. Thread-safe; the caller owns it exclusively until it
# hands it back to `_release_field`.
func _take_field() -> IslandField:
	_pool_mutex.lock()
	var f: IslandField = _field_pool.pop_back() if not _field_pool.is_empty() else null
	_pool_mutex.unlock()
	# Cloning outside the lock: it is the slow part, and holding the mutex across
	# it would serialise exactly the threads this exists to keep apart.
	return f if f != null else _field.clone()


func _release_field(f: IslandField) -> void:
	_pool_mutex.lock()
	_field_pool.append(f)
	_pool_mutex.unlock()


# Runs on a worker thread. Touches only the `IslandField` it has borrowed, the
# node's read-only placement exports, and the mutex-guarded result list — no scene
# tree, no MultiMesh, no engine singletons.
func _tile_task(key: Vector2i, off: Vector3, lo: Vector3, hi: Vector3,
		force: bool) -> void:
	var f := _take_field()
	var out := _tile_work(key, f, off, lo, hi, force)
	_release_field(f)
	_done_mutex.lock()
	_done.append(out)
	_done_mutex.unlock()


# Probe the tile, and mesh it if the probe says it is in range. Both halves are
# field sampling, so both belong on whatever thread called this; the main thread
# only ever sees the finished dictionary.
#
# `lo`/`hi` are the scan cell the task was handed out from, which is a frame or two
# stale by the time this runs. That is fine — it decides whether to mesh, and a
# tile wrongly deferred is picked up by the next scan with its real height band now
# known.
#
# `force` is what a prescatter hands in, and it is not an optimisation: the whole
# point of prescattering is to build tiles the camera is nowhere near, so the range
# test that makes streaming cheap is exactly wrong there. Without it a prescatter
# would probe every tile, mesh the handful in view and report itself done.
func _tile_work(key: Vector2i, f: IslandField, off: Vector3, lo: Vector3,
		hi: Vector3, force: bool) -> Dictionary:
	var band := _probe_tile(key, f)
	if not force and _band_dist_sq(key, band.x, band.y, lo, hi) \
			> view_distance * view_distance:
		return {"key": key, "y0": band.x, "y1": band.y}
	return _build_tile(key, f, off, band)


# Evaluate every cell of a tile once and pack the survivors into one finished
# instance buffer per sprite variant, in the render space `off` describes. A pure
# function of (key, field, off), which is what makes it safe to run anywhere.
func _build_tile(key: Vector2i, f: IslandField, off: Vector3, band: Vector2) -> Dictionary:
	var n := _meshes.size()
	var lists: Array = []
	for i in range(n):
		lists.append([])
	var total := 0
	var y0 := INF
	var y1 := -INF
	var side := maxi(tile_cells, 1)
	var base := key * side
	for dz in range(side):
		for dx in range(side):
			var r := _evaluate_cell(Vector2i(base.x + dx, base.y + dz), f)
			if not r["valid"]:
				continue
			# A cell yields a LIST — one plant for a tree, a clump for the
			# understory. See `bush_per_cell`.
			for p in (r["plants"] as Array):
				var v: int = p["sprite"]
				if v < 0 or v >= n:
					continue   # a class with no sprites wired up; see `_evaluate_cell`
				(lists[v] as Array).append(p)
				total += 1
				var y: float = (p["pos"] as Vector3).y
				y0 = minf(y0, y)
				y1 = maxf(y1, y)
	var bufs: Array = []
	for i in range(n):
		bufs.append(_pack_tile(lists[i], off))
	# Tighten the probe's estimate to the plants that actually stand here. A tile
	# that grew none keeps the estimate: it emits nothing either way, and INF in the
	# band would poison `_tile_dist_sq`. The band is the BASE's range, not the
	# canopy's — the shader's fades are driven from the instance origin too, so the
	# two agree.
	if y1 < y0:
		y0 = band.x
		y1 = band.y
	return {"key": key, "bufs": bufs, "n": total, "y0": y0, "y1": y1, "off": off}


# Move finished tiles from the worker list into the tile table. Called at the top
# of every scan. Returns how many landed, which is what the prescatter counts its
# progress in — the cursor cannot serve, since a lane claims a tile well before it
# finishes one.
func _collect_done() -> int:
	_done_mutex.lock()
	var batch: Array = _done
	_done = []
	_done_mutex.unlock()
	for r in batch:
		_install_tile(r)
	return batch.size()


func _install_tile(r: Dictionary) -> void:
	var key: Vector2i = r["key"]
	_pending.erase(key)
	var rec: Dictionary = _tiles.get(key, {})
	_tiles[key] = rec
	rec["y0"] = r["y0"]
	rec["y1"] = r["y1"]
	if not r.has("bufs"):
		return   # probed only: out of range when the worker looked
	var bufs: Array = r["bufs"]
	# A rebase landed while this tile was on a worker, so it was packed against an
	# origin the world has since moved off. Three floats an instance puts it right,
	# which beats throwing away a tile's worth of field samples.
	var drift: Vector3 = (r["off"] as Vector3) - _origin_offset
	if drift != Vector3.ZERO:
		_shift_bufs(bufs, drift)
	rec["bufs"] = bufs
	rec["n"] = r["n"]
	if _bake_open and not r.get("from_bake", false):
		# Held for the next scene, which on W3 is the walk home from a battle. The
		# record goes in with the origin it was PACKED against rather than the one
		# it was just patched to, so a bake taken either side of a rebase installs
		# the same way — `drift` above is what makes that work, and it is the same
		# three floats whether the tile came off a lane or out of the store.
		_bake.put_tile(key, {"bufs": bufs, "n": r["n"], "y0": r["y0"],
				"y1": r["y1"], "off": _origin_offset})
	# New bytes under a selection that `_fill`'s fingerprint would call unchanged —
	# the tile was already in the scanned box, it just had nothing in it yet. Without
	# this the first tile to land after a fill that already ran is silently dropped.
	_fill_dirty = true


# Pack one variant's plants into a MultiMesh instance buffer. The array is a local
# with a single reference, so `resize` once and write by index is an in-place fill
# rather than a copy per element.
func _pack_tile(items: Array, off: Vector3) -> PackedFloat32Array:
	var buf := PackedFloat32Array()
	buf.resize(items.size() * _STRIDE)
	var k := 0
	for r in items:
		var b: Basis = r["basis"]
		var o: Vector3 = (r["pos"] as Vector3) - off
		buf[k] = b.x.x
		buf[k + 1] = b.y.x
		buf[k + 2] = b.z.x
		buf[k + 3] = o.x
		buf[k + 4] = b.x.y
		buf[k + 5] = b.y.y
		buf[k + 6] = b.z.y
		buf[k + 7] = o.y
		buf[k + 8] = b.x.z
		buf[k + 9] = b.y.z
		buf[k + 10] = b.z.z
		buf[k + 11] = o.z
		# Custom-data vec4: .x is this plant's crater burn, .yzw reserved (0). The
		# PackedFloat32Array came zero-filled from `resize`, so the three spares need no
		# write — but .x always does, or a plant would inherit the last one's burn.
		buf[k + _CUSTOM_OFF] = float(r.get("burn", 0.0))
		k += _STRIDE
	return buf


# Concatenate the visible tiles' buffers into each MultiMesh. One pass per sprite
# variant, each accumulating into a LOCAL array: `append_array` on a packed array
# with one reference is a memcpy onto the end, whereas appending into an array held
# inside another array would copy the whole thing on every tile.
#
# BY CLASS, NOT BY SPRITE, and that is the whole of the triangle cut. Each class
# takes the tiles inside ITS OWN fade rather than inside the scatter's outer view
# distance, so the numerous short-banded classes stop being submitted across ground
# where the shader had already dithered them to nothing. See `Distance` for why the
# cull and the fade are the same number.
#
# AND A CLASS WHOSE CHOICE DID NOT CHANGE IS NOT RE-UPLOADED. The selection is a
# function of the scan CELL, so most crossings move no tile across any band — and a
# class whose fade already reaches past the whole island never moves one at all: it
# packs on the first scan and is never touched again, which is exactly the
# behaviour the entire scatter had before the bands were split. The fingerprint is
# a rolling hash of the selected keys in walk order, which is deterministic.
#
# What a fingerprint cannot see is the BUFFERS changing under an unchanged
# SELECTION — a tile landing, a rebase — so both of those set `_fill_dirty`
# instead, and it forces every sprite through regardless.
#
# THE RE-PACK IS THEN SPREAD OVER FRAMES, because a crossing that moves tiles
# across all three bands at once asks for the whole world in one of them. See
# `fill_sprites_per_scan`.
func _fill(visible: Array) -> void:
	# --- decide, per class, what each of them is looking at ---------------------
	# All three selections are taken here even when nothing will be re-packed from
	# them: they are a few hundred float compares each, and a sprite carried over
	# from a previous scan re-packs against the CURRENT selection rather than the
	# stale one it was queued for, which is both cheaper and more correct.
	var sels: Array = []
	for cls in range(_class_span.size()):
		var span: Vector2i = _class_span[cls]
		var sel: Array = []
		if span.y > 0:
			var lim: float = _class_view_sq[cls]
			var fp := 1
			for e in visible:
				if float(e[0]) > lim:
					continue
				sel.append(e[1])
				fp = ((fp * 1000003) ^ int(e[2])) & 0x3fffffff
			if int(_fill_fp[cls]) != fp:
				_fill_fp[cls] = fp
				for i in range(span.x, span.x + span.y):
					_fill_owed[i] = 1
		sels.append(sel)

	# --- re-pack as many of the owed sprites as the budget allows ---------------
	# `_fill_dirty` suspends the budget outright, and has to: it means the BYTES
	# moved under an unchanged selection (a rebase, a tile landing), so a sprite
	# held back would keep drawing the old ones — which after a rebase is the whole
	# island at an origin eight kilometres away.
	# `scan_cell` 0 suspends it too, and for the reason that switch exists at all:
	# it is what a render harness sets to make its stills exact, and a still taken
	# of a fill that is two sprites behind is exactly the kind of inexactness it was
	# turning off. Nothing ships with it.
	var budget := maxi(fill_sprites_per_scan, 1)
	if _fill_dirty or scan_cell <= 0.0:
		budget = _meshes.size()
	if _fill_dirty:
		_fill_owed.fill(1)
		_fill_dirty = false
	var owed := 0
	for cls in range(_class_span.size()):
		var span: Vector2i = _class_span[cls]
		for i in range(span.x, span.x + span.y):
			if _fill_owed[i] == 0:
				continue
			if budget <= 0:
				owed += 1
				continue
			budget -= 1
			_fill_owed[i] = 0
			var out := PackedFloat32Array()
			for bufs in (sels[cls] as Array):
				out.append_array((bufs as Array)[i])
			var mm: MultiMesh = _meshes[i]
			mm.instance_count = out.size() / _STRIDE
			if not out.is_empty():
				mm.buffer = out
	# Come back next frame past the scan-cell gate, or the sprites left owed here
	# would wait for the camera to cross another cell before catching up.
	if owed > 0:
		_force_rescan = true


# A tile key as one integer, for `_fill`'s selection fingerprint. It only has to be
# well spread and stable within a session; these are the two primes the placement
# hash already uses.
static func _key_hash(key: Vector2i) -> int:
	return ((key.x * 73856093) ^ (key.y * 19349663)) & 0x3fffffff


# Select and pack immediately, for the two moments a prescattered world cannot wait
# for its next ordinary scan: the frame the build completes (nothing has reached a
# MultiMesh yet, so waiting is a bald island) and the frame the origin is rebased
# under it (every buffer has just been patched, so waiting is an island of
# vegetation eight kilometres from the ground it grows on).
#
# It is `_rescan` and nothing else — there is no separate static packing path any
# more, which is the point. A prescattered scan dispatches no work and prunes
# nothing (both guard on `_prescattered`), so what is left of it IS the selection,
# and having one code path means the set the build hands over is bit-identical to
# the one the next scan would have chosen.
#
# Around the LAST LOGICAL EYE rather than the camera, for the rebase case: see
# `_eye`. The camera's shift and this node's are two independent visits by
# `floating_origin` in no defined order, and the logical eye is the one quantity a
# rebase leaves alone.
func _refill_static() -> void:
	_force_rescan = true
	# Both callers mean "completely, this frame", so the spreading budget is
	# suspended rather than left to converge over the next few scans. `_fill_dirty`
	# is already true at both of them; setting it here is what makes that a property
	# of this function instead of a coincidence of its call sites.
	_fill_dirty = true
	_rescan(_eye if _have_eye else _anchor_eye())
	_static_bounds()


# The eye to select around for the FIRST fill, when no scan has ever run to leave
# a logical one behind: the camera when there is one, and the logical origin when
# there is not, matching what `_prescatter_tiles` anchors on. A headless harness
# that finishes a prescatter before its first frame has no viewport, and a crash
# there would be a crash in the only path that builds the world.
func _anchor_eye() -> Vector3:
	var vp := get_viewport()
	var cam := vp.get_camera_3d() if vp != null else null
	if cam != null:
		return cam.global_position + _origin_offset
	return Vector3.ZERO


# Recentre each MultiMesh's cull box on the SCAN CELL (render space): the instances
# cluster around the camera rather than the render origin, so a box pinned to the
# origin would frustum-cull the whole field the moment the camera looked away.
# Sized off the cell rather than the eye for the same reason everything else here
# is — it has to stay right for every eye the cell holds.
func _update_bounds(lo: Vector3, hi: Vector3) -> void:
	# A prescattered world keeps the island-sized box `_static_bounds` gave it. The
	# selection moves with the camera there too, so a camera box would not be WRONG
	# — but it would be rewritten on every scan to no purpose, and an oversized box
	# only ever costs a frustum test that would have passed.
	if _prescattered:
		return
	var r := Vector3.ONE * (view_distance + 60.0)
	var box := AABB(lo - r, (hi - lo) + r * 2.0)
	for inst in _instances:
		if inst != null:
			inst.custom_aabb = box


# The box every prescattered plant COULD stand in, render space, plus a canopy's
# worth of slack. Set once when the build completes and again after a rebase, which
# are the only two events that move it.
#
# Deliberately the whole island rather than the current selection. A box has to
# stay right for every eye until something rewrites it, and the selection changes
# under a camera that has merely walked a few metres; sizing it to the island makes
# it right for all of them and costs one frustum test that would have passed
# anyway. The per-class cut in `_fill` is what does the culling here — this only
# has to avoid getting in its way.
func _static_bounds() -> void:
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for key in _tiles:
		var rec: Dictionary = _tiles[key]
		if not rec.has("bufs") or int(rec["n"]) == 0:
			continue
		var x0 := float(key.x) * _tile_size - _origin_offset.x
		var z0 := float(key.y) * _tile_size - _origin_offset.z
		lo = Vector3(minf(lo.x, x0), minf(lo.y, float(rec["y0"]) - _origin_offset.y),
				minf(lo.z, z0))
		hi = Vector3(maxf(hi.x, x0 + _tile_size),
				maxf(hi.y, float(rec["y1"]) - _origin_offset.y), maxf(hi.z, z0 + _tile_size))
	if lo.x > hi.x:
		return
	var pad := Vector3(0.0, maxf(tree_height.y, 20.0), 0.0)
	var box := AABB(lo - pad, (hi - lo) + pad * 2.0)
	for inst in _instances:
		if inst != null:
			inst.custom_aabb = box


# Forget tiles outside the scanned box plus a margin. Bounded by the TILE box
# rather than by a radius, which keeps the invariant simple: every tile in the box
# is known, and nothing in the box is ever dropped, so a tile can never be evicted
# and immediately re-meshed.
func _prune_tiles() -> void:
	# Guarded HERE rather than only at the call site, because "a prescattered world
	# never loses a tile" is a property of the world and not of one code path. The
	# vegetation is complete by construction and there is no machinery left to
	# notice a hole in it, let alone refill one.
	if prescatter:
		return
	if not _box_valid:
		return
	var m := int(ceil(keep_margin / _tile_size)) + 1
	var lo := _box_min - Vector2i(m, m)
	var hi := _box_max + Vector2i(m, m)
	var drop: Array = []
	for key in _tiles:
		if key.x < lo.x or key.x > hi.x or key.y < lo.y or key.y > hi.y:
			drop.append(key)
	for key in drop:
		_tiles.erase(key)


## Plants currently SUBMITTED, across every sprite — what the frame actually costs,
## which under the per-class fades is a fraction of what is held. Pair it with
## `total_plant_count()`; the ratio between them is the cut. Handy for debug
## overlays.
func live_plant_count() -> int:
	var n := 0
	for mm in _meshes:
		n += mm.instance_count
	return n


## Tiles held, and how many of them are meshed. Handy for debug overlays, and for
## the tests that assert the streaming actually streams.
func tile_counts() -> Vector2i:
	var built := 0
	for key in _tiles:
		if (_tiles[key] as Dictionary).has("bufs"):
			built += 1
	return Vector2i(_tiles.size(), built)


## Tiles in view that still owe work — 0 once the neighbourhood is complete. Handy
## for debug overlays and for tests that wait the fill out.
func pending_tiles() -> int:
	return _todo


## Sprite buffers still owed a re-pack, which `fill_sprites_per_scan` spreads over
## frames. 0 means every MultiMesh agrees with the selection of the last scan.
##
## A harness driving `_rescan` by hand has to drive it until this reaches 0 before
## reading a count or taking a shot; `_process` gets there on its own, because a
## scan that leaves work owed forces the next one.
func pending_fill() -> int:
	var n := 0
	for v in _fill_owed:
		n += int(v)
	return n


# A worker holds a reference to this node's method, so leaving the tree while one
# is in flight is a use-after-free waiting to happen. Wait them out; they are one
# tile of arithmetic each, so this is milliseconds, not a stall.
func _exit_tree() -> void:
	# Retire the prescatter lanes before waiting on them: a lane loops until the
	# list runs out, so waiting on one that still has five hundred tiles to claim
	# would stall the exit for the rest of the build rather than for a tile of it.
	_pre_mutex.lock()
	_pre_width = 0
	_pre_mutex.unlock()
	_pre_lanes.join()
	for key in _pending:
		var id: int = _pending[key]
		if id >= 0:
			WorkerThreadPool.wait_for_task_completion(id)
	_pending.clear()
	_done_mutex.lock()
	_done = []
	_done_mutex.unlock()


# ---------------------------------------------------------------- prefilling

## Called every frame by whatever is covering the world — `SCRIPT_world_loading_screen.gd`
## — for as long as it is up. That is the whole contract: the prescatter runs wide
## while this keeps arriving and narrows to a single lane when it stops. See
## `_prescatter_width`.
##
## Stepping is NOT the same signal and cannot stand in for it: a loading screen
## does not begin stepping its scatters until the terrain is built, which is most
## of the time it is up.
func prefill_covered() -> void:
	_pre_step_frame = Engine.get_process_frames()


## One slice of the up-front fill, driven by `SCRIPT_world_loading_screen.gd` so the
## vegetation is already down when the screen lifts rather than sprouting around
## the player over the first second of play. True when there is no more to do.
func prefill_step() -> bool:
	# Stepping implies covering — the only caller is a screen — so a host that
	# steps without announcing itself still gets the wide build.
	prefill_covered()
	if not _ready_ok:
		return _field == null or material == null
	if prescatter:
		return _prescatter_step()
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return true
	_rescan(cam.global_position + _origin_offset, maxi(prefill_eval_per_step, 1))
	_prefill_total = maxi(_prefill_total, _todo)
	return _todo <= 0


## 0..1 across the up-front fill, for a progress bar.
func prefill_ratio() -> float:
	if _prefill_total <= 0:
		return 1.0 if _ready_ok else 0.0
	return clampf(1.0 - float(_todo) / float(_prefill_total), 0.0, 1.0)


## The line `SCRIPT_world_loading_screen.gd` prints while this scatter fills, alongside
## the terrain's own `meshing terrain N / M`. The screen keeps no vocabulary of its
## own — it knows nothing about chunks or plants — so the figure that means
## something for THIS node is named here rather than there.
##
## IT COUNTS WHAT IS HELD, NOT WHAT IS UPLOADED, and the difference is the whole
## reason this reads well. Under `prescatter` nothing reaches a MultiMesh until the
## single `_refill_static()` on the last tile, so `live_plant_count()` sits at 0 for
## the whole minute the bar is up and then jumps — a readout that looks like a hang
## and then a glitch. `total_plant_count()` climbs with every tile that lands, which
## is the work being waited on. (And once the bar lifts the two still differ, by the
## understory the per-class fades are not currently submitting.)
func prefill_label() -> String:
	var held := total_plant_count()
	# Silent until the first tile lands, like `grass_scatter`'s. The screen puts this
	# up from the first frame of the world build now, and "planting 0 plants 0 / 0
	# tiles" under a survey that has not reached the vegetation yet reads as a broken
	# counter rather than as one with nothing to say.
	if held <= 0:
		return ""
	var n := _thousands(held)
	if not prescatter:
		return "planting %s plants" % n
	var p := prescatter_progress()
	return "planting %s plants   %d / %d tiles" % [n, p.y - p.x, p.y]


# Local by design. `SCRIPT_grass_scatter.gd` keeps its own copy, and the alternative is
# one of two shipping scripts preloading the other for eight lines of string work;
# the test harnesses each carry one for the same reason.
static func _thousands(n: int) -> String:
	var s := str(n)
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	return out


# ---------------------------------------------------------------- prescattering

# One slice of "build the whole world's vegetation". Same worker pool, same field
# clones, same install path as the streamer — what changes is only WHICH tiles are
# asked for and that the range test on the worker is suppressed.
func _prescatter_step() -> bool:
	if not _pre_ready:
		# Filtered HERE, on the main thread, rather than in the claim loop: a lane
		# cannot read `_tiles` safely, and there is nothing to filter after this
		# point anyway — under `prescatter` no ordinary scan ever meshes anything
		# (`_rescan` guards both `todo` branches on it), so the set of tiles that
		# arrived early is fixed before the first lane starts.
		_pre_queue = []
		_pre_baked = []
		_pre_baked_next = 0
		for key in _prescatter_tiles():
			if _tiles.has(key) and (_tiles[key] as Dictionary).has("bufs"):
				continue   # already meshed by a scan that ran before this began
			# A tile the store already holds costs a dictionary lookup instead of
			# a tile of field sampling. Sorted out HERE, in the same main-thread
			# pass that builds the queue, so a lane never claims one and the
			# progress total counts both kinds — see `_prescatter_take_baked`.
			if _bake_open and _bake.has_tile(key):
				_pre_baked.append(key)
			else:
				_pre_queue.append(key)
		_pre_cursor = 0
		_pre_installed = 0
		_pre_ready = true
		_prefill_total = maxi(_pre_queue.size() + _pre_baked.size(), 1)
		if not _pre_baked.is_empty():
			print("[veg_scatter] %s of %s tiles came out of the bake" % [
					_thousands(_pre_baked.size()),
					_thousands(_pre_baked.size() + _pre_queue.size())])
	_pre_installed += _prescatter_take_baked()
	_pre_installed += _collect_done()

	if use_threads:
		_prescatter_staff()
	elif _pre_cursor < _pre_queue.size():
		# Debug path: one tile per step on the main thread, so the bar keeps moving.
		var key: Vector2i = _pre_queue[_pre_cursor]
		_pre_cursor += 1
		_install_tile(_tile_work(key, _field, _origin_offset,
				Vector3.ZERO, Vector3.ZERO, true))
		_pre_installed += 1

	_pre_owed = _pre_queue.size() + _pre_baked.size() - _pre_installed
	_todo = _pre_owed
	if _pre_owed > 0:
		return false

	# Complete. From here the TILE set is fixed — nothing is meshed, probed, pruned
	# or re-meshed again — and what a scan still does is choose which of those tiles
	# each class submits. This is the first upload of the run: until now every
	# finished tile has only been filed in `_tiles`.
	_prescattered = true
	_refill_static()
	return true


# Take tiles out of `VegBake`, a batch a step. Returns how many landed, which is
# what the caller counts progress in — the same currency `_collect_done` returns.
#
# BATCHED RATHER THAN DRAINED, and the batch is not about the lookup. Installing a
# baked tile is a dictionary write and a reference copy; a thousand of them in one
# frame would still be under a millisecond. What the batch buys is the BAR: a
# prescatter that completes in a single step reports 0/1020 and then done, which
# on a re-entry is the whole loading screen going from empty to gone in two frames
# and reads as a glitch rather than as a fast load. Stepping it lets the screen
# draw the thing it is for.
#
# `prefill_eval_per_step` is a CELL budget everywhere else in this file; here it
# stands in for tiles, which is the same knob meaning "how much of the up-front
# fill may land on one frame" one unit coarser. A tile out of the store costs
# about as much as one cell of a tile that has to be built.
func _prescatter_take_baked() -> int:
	var left := _pre_baked.size() - _pre_baked_next
	if left <= 0:
		return 0
	var n := mini(left, maxi(prefill_eval_per_step, 1))
	for i in n:
		var key: Vector2i = _pre_baked[_pre_baked_next + i]
		var rec: Dictionary = _bake.take(key)
		if rec.is_empty():
			# The store answered `has_tile` and then had nothing, which can only
			# happen if something cleared it under a build in flight. Put the tile
			# on the meshing queue rather than install it as bald ground: the slot
			# still counts as consumed here, and the queue entry it becomes brings
			# its own total and its own install with it.
			_pre_queue.append(key)
			continue
		# `from_bake` keeps `_install_tile` from putting it straight back, which
		# would be harmless and would also re-charge its bytes and its put count
		# on every re-entry for the rest of the session. `take` has already given
		# this record a buffer list of its own — see `VegBake._detached`.
		rec["key"] = key
		rec["from_bake"] = true
		_install_tile(rec)
	_pre_baked_next += n
	return n


# Is something still holding a screen up in front of the world?
#
# `prefill_step()` is the signal, and it is the right one because it means exactly
# what is being asked: a loading screen steps its scatters every frame while it is
# up and stops the moment it clears, so "were we stepped recently" IS "is the
# player still looking at a bar". Nothing has to be wired, and a scene with no
# loading screen at all — a test harness, a zone that streams — reads as uncovered
# from its first frame, which is the correct answer there too.
#
# The slack is because node order decides whether the screen's step lands before
# or after this node's `_process` in the same frame, and W2 happens to put
# VegScatter first. Two frames is enough for either order and short enough that
# the throttle takes hold the moment the bar goes.
const _COVER_SLACK := 2


func _prescatter_covered() -> bool:
	return _pre_step_frame >= 0 \
			and Engine.get_process_frames() - _pre_step_frame <= _COVER_SLACK


# Lanes to run right now.
#
# WIDE BEHIND THE SCREEN, ONE IN FRONT OF IT, and that asymmetry is the whole
# point rather than a safety margin. Behind a loading screen the machine is ours
# and the only thing that matters is finishing; the main thread has a bar to draw
# and nothing else. Once the screen clears the player is flying over the island
# with a renderer to feed, and a build that keeps every core busy shows up as
# exactly what it is — a long stretch at a fraction of the frame rate that snaps
# back the instant the last tile lands.
#
# That stretch is meant to be empty: on a machine where the build fits behind the
# bar there is no uncovered frame to throttle. It is not empty in practice, which
# is why this exists — `world_loading_screen.scatter_timeout` gives up on a wall
# clock and hands the player a world with the build still running, and the width
# is what decides whether that costs them the frame rate or just some bald ground.
# `tests/PROBE_veg_timeline.gd` measures both halves.
func _prescatter_width() -> int:
	if not _prescatter_covered():
		return 1
	if prescatter_in_flight > 0:
		return prescatter_in_flight
	# One below the core count, matching `island_world._pregen_begin`: the pool
	# sizes itself the same way and the main thread still has work.
	return maxi(1, OS.get_processor_count() - 1)


# Bring the running lanes up to the current width, and publish that width for the
# lanes to retire against. Lifted from `island_world._pregen_staff_lanes`, which
# is the same problem solved once already — including which scheduler runs it.
#
# ON THREADS OF ITS OWN, not on `WorkerThreadPool`, and unlike what this used to
# do. See `prescatter_in_flight` for the measurement that got it off the pool's
# LOW priority — low-priority tasks are capped at a fraction of the pool, one
# thread on a four-core box, so the old per-tile dispatch was a single worker
# however many it asked for — and `SCRIPT_build_lanes.gd` for why the high-priority
# lanes that replaced it could not stay there either: two lane pools sized from
# the core count left the pool with no free thread for the ENGINE'S own jobs, and
# Jolt blocked the main thread for the whole build.
#
# The streamer below stays on the pool, at low priority, deliberately: those tasks
# are short and the cap is a feature, since a tile that arrives a frame later
# costs nothing and a stolen core costs a frame.
func _prescatter_staff() -> void:
	_pre_mutex.lock()
	_pre_width = _prescatter_width()
	# Nothing to staff a queue for that is already handed out: without this the
	# tail of the build would spawn lanes every frame just to have them exit.
	var need := 0 if _pre_cursor >= _pre_queue.size() else _pre_width - _pre_live
	if need > 0:
		_pre_live += need
	_pre_mutex.unlock()
	_pre_lanes.spawn(need, _prescatter_lane)
	_pre_lanes.reap()


# One lane. Borrows a field once and meshes tiles off the shared cursor until the
# list runs out or the lane is retired by a width cut — so a narrowing costs one
# tile of latency rather than interrupting anything.
#
# Retirement is by HEADCOUNT rather than by lane identity, the way the terrain's
# lanes do it: a lane that sees more lanes live than the current width takes
# itself out of the count and stops, and because the test and the decrement happen
# under one lock, exactly the surplus retires and the rest carry on.
#
# Touches only the field it has borrowed, the two mutex-guarded shared values and
# the result list. No scene tree, no MultiMesh.
func _prescatter_lane() -> void:
	var f := _take_field()
	while true:
		_pre_mutex.lock()
		var i := -1
		var off := _origin_offset
		if _pre_live <= _pre_width and _pre_cursor < _pre_queue.size():
			i = _pre_cursor
			_pre_cursor += 1
		else:
			_pre_live -= 1
		_pre_mutex.unlock()
		if i < 0:
			break
		var out := _tile_work(_pre_queue[i], f, off, Vector3.ZERO, Vector3.ZERO, true)
		_done_mutex.lock()
		_done.append(out)
		_done_mutex.unlock()
	_release_field(f)


# Every tile key that could hold a plant, island by island.
#
# ISLAND BY ISLAND rather than by sweeping the whole radius, because the radius is
# mostly void: W2's is 3,600 m around a single 1,525 m island, so a disc sweep
# would enumerate several times as many tiles as touch land, and every one of the
# extras is a worker probe that samples the field five times to conclude nothing is
# there.
func _prescatter_tiles() -> Array:
	var out: Array = []
	if _field == null:
		return out
	# Where the world was built around. The camera when there is one — matching
	# `island_world._pregen_begin`, which anchors on the camera for the same reason
	# — and the logical origin when there is not, so a headless harness that
	# enumerates before the first frame still gets the island rather than a crash on
	# a null viewport.
	var anchor := Vector3.ZERO
	var vp := get_viewport()
	var cam := vp.get_camera_3d() if vp != null else null
	if cam != null:
		anchor = cam.global_position + _origin_offset
	var r := prescatter_radius
	if r <= 0.0:
		# Match the terrain that was built for it, so the vegetation cannot reach
		# past the ground it stands on.
		r = float(_world.get("view_distance")) if _world != null else view_distance
		if r <= 0.0:
			r = view_distance
	var islands: Array = _field.islands_in_rect(anchor.x - r, anchor.z - r,
			anchor.x + r, anchor.z + r)
	var seen := {}
	for isl in islands:
		var c: Vector2 = isl.center
		if Vector2(anchor.x, anchor.z).distance_to(c) > r + _field.island_extent(isl):
			continue
		var e: float = _field.island_extent(isl)
		var t0 := Vector2i(floori((c.x - e) / _tile_size), floori((c.y - e) / _tile_size))
		var t1 := Vector2i(floori((c.x + e) / _tile_size), floori((c.y + e) / _tile_size))
		for tz in range(t0.y, t1.y + 1):
			for tx in range(t0.x, t1.x + 1):
				var key := Vector2i(tx, tz)
				if seen.has(key):
					continue
				# Corner-to-centre test against the island's disc: a tile whose
				# nearest point is already past the coastline can hold no plant.
				var nx := clampf(c.x, float(tx) * _tile_size, float(tx + 1) * _tile_size)
				var nz := clampf(c.y, float(tz) * _tile_size, float(tz + 1) * _tile_size)
				if Vector2(nx, nz).distance_to(c) > e:
					continue
				seen[key] = true
				out.append(key)
	return out


## Tiles the prescatter still owes, and how many it started with. Its OWN counter,
## not `_todo` — the scan taken the moment the build completes would overwrite that
## one with the streamer's figure.
func prescatter_progress() -> Vector2i:
	return Vector2i(_pre_owed, _prefill_total)


## Every plant the scatter is holding, across all tiles, whether or not it is
## currently emitted to a MultiMesh. This is the count `prescatter` exists to make
## equal to the world's vegetation — and it is deliberately NOT what is drawn; see
## `live_plant_count()` for that.
func total_plant_count() -> int:
	var n := 0
	for key in _tiles:
		var rec: Dictionary = _tiles[key]
		if rec.has("n"):
			n += int(rec["n"])
	return n


## True once every tile of the bounded world is built and kept — i.e. nothing will
## be meshed, pruned or re-meshed for the rest of the session.
func is_prescattered() -> bool:
	return _prescattered


# Decide whether a grid cell grows a plant, WHICH CLASS it grows, and which sprite
# of that class. Pure function of the cell and the field, so it is stable across
# visits and across a rebase — and so it can run on a worker thread, which is why
# the field is a parameter rather than the node's own: a worker gets its own clone.
#
# ONE ROLL DOES BOTH JOBS. `keep` is uniform on [0, 1); the three class weights are
# laid end to end and whichever band `keep` lands in is the class, with everything
# past their sum growing nothing. That is exactly a weighted choice plus a keep
# test, in one number, and it is what guarantees a cell can never grow two CLASSES.
#
# It returns a LIST of plants, not one — a tree cell yields a single tree, an
# understory cell yields `bush_per_cell` / `fern_per_cell` of them jittered across
# the cell. They share the cell's one field sample, which is the whole point: the
# sample is the entire cost here and the extra plants are free of it.
func _evaluate_cell(cell: Vector2i, f: IslandField) -> Dictionary:
	var hx := _hash(cell.x, cell.y, f.world_seed ^ 0x7EE501)
	var keep := _rand(hx, 1)

	# The clumping noises, one per class and each on its own field, so a thicket of
	# scrub is not thereby a stand of firs. All three are hash arithmetic — no field
	# sample yet.
	var tree_clump := 0.5 + 0.5 * _value_noise(cell, 0x1)
	var fern_clump := 0.5 + 0.5 * _value_noise(cell, 0x51F3)
	# The bushes' is THRESHOLDED rather than scaled, which is the difference between
	# fields that are evenly speckled with scrub and fields that are mostly bare
	# with thickets in them. It also reads the noise RAW rather than through the
	# `0.5 + 0.5 *` compression the other two use — that compression is what keeps
	# a forest from having bald patches in it, and it is exactly what has to go if
	# the threshold is to reach zero anywhere. See `bush_clump_lo`/`_hi`.
	var bush_clump := smoothstep(minf(bush_clump_lo, bush_clump_hi - 1e-3),
			bush_clump_hi, _value_noise(cell, 0x2B7))

	# The keep roll's CEILING, tested BEFORE the field is touched. Each class weight
	# is `lerp(open, forest, forest_mask) * clump`, and a lerp between two numbers
	# cannot exceed the larger of them — so a cell that fails against the sum of
	# those larger numbers fails whatever the forest mask turns out to be, and the
	# sample that would have told us the forest mask is dead weight.
	#
	# Exactly equivalent, not an approximation: the same cells grow the same plants
	# in the same places. Worth having because the sample is the ENTIRE cost of this
	# function — `IslandField.sample` is ~0.15 ms against a few dozen hashed
	# arithmetic ops.
	# Capped at 1, because the priority clamp below caps the true total there too —
	# without which this stops rejecting anything at all the moment the three
	# densities sum past one, which is exactly the case a thick forest is tuned
	# into. The cap costs nothing and keeps the early-out honest; what it cannot do
	# is save a sample in a wood that really is saturated, because in one every cell
	# grows something and there is nothing to reject.
	var ceiling := minf(maxf(tree_open_density, tree_forest_density) * tree_clump
			+ maxf(bush_open_density, bush_forest_density) * bush_clump
			+ maxf(fern_open_density, fern_forest_density) * fern_clump, 1.0)
	if keep > ceiling:
		return {"valid": false}

	var jx := (_rand(hx, 2) - 0.5) * 0.85 * veg_grid
	var jz := (_rand(hx, 3) - 0.5) * 0.85 * veg_grid
	var wx := (float(cell.x) + 0.5) * veg_grid + jx
	var wz := (float(cell.y) + 0.5) * veg_grid + jz

	var s := f.sample(wx, wz)
	if not s.get("on_land", false):
		return {"valid": false}
	# Rock and sand grow nothing. Grass and soil both can — which matters because
	# `IslandField.forest_litter` deliberately turns part of the turf under a canopy
	# into needle floor, and gating on "grass wins" alone would have made the
	# densest woods the one place a tree could not stand.
	var surf: String = s.get("surface", "")
	if surf == "rock" or surf == "sand":
		return {"valid": false}
	if s.get("slope", 1.0) > max_slope:
		return {"valid": false}
	if s.get("flatten", 1.0) > max_flatten:
		return {"valid": false}
	var w: Color = s.get("weights", Color(0, 0, 0, 0))
	if w.r + w.g < 0.6:
		return {"valid": false}

	# THE CRASH SITE: A BARE CRATER RINGED BY BURNING FOREST, and this class carries both
	# halves of it. Everything from the lip crest INWARD clears — floor and inner slope
	# alike; the collar of forest from the crest outward stands and burns, deepest into the
	# fire nearest the impact and fading to green. NOT past it — see `crater_burn_peak`,
	# which is the difference between a wood alight and a ring of cold poles.
	#
	# `SCRIPT_grass_scatter.gd` needs no clearing rule of its own — it weights its tufts by the
	# GRASS channel, which `IslandField.splat_weights` has already taken to zero across
	# the crater — but it DOES carry the same per-plant burn, so the tufts that survive
	# in the collar char with the trees rather than staying a green lawn under a fire.
	# The clearing rule has to be explicit here because the test above passes on
	# `w.r + w.g`, and the crater's ground is soil-dominant — indistinguishable from a
	# build pad or a needle floor by that measure.
	#
	# CLEARED ON THE RAW CRATER WEIGHT, kept-and-burnt below `crater_veg_keep`. See that
	# export for why the raw weight and not `crater_burn`: the weight is what separates a
	# floor from a lip, and `crater_burn` is flat across both.
	#
	# THE RAMP RUNS OUTWARD, finishing at `crater_veg_keep` rather than starting there —
	# see that export. Bare at the crest and everywhere inside it; thinning back in across
	# `crater_veg_band` of weight, which is spent on the outer drift.
	#
	# A ROLL, NOT A CUT. Rolled per cell on its own lane, so the collar's inner edge thins
	# out plant by plant the way `veg_burn`'s spreading front does instead of stamping a
	# circle through the wood. The two falloffs — this roll and the burn below — overlap
	# into one gradient: bare, then thinly scattered plants well alight, then a burning
	# stand, then green.
	var cw := clampf(float(s.get("crater", 0.0)), 0.0, 1.0)
	# How burnt the plant LOOKS — the same remap, on the same weight, as the charred
	# ground under it, so the two can never disagree about WHERE the fire is; scaled by
	# `crater_burn_peak` so they are allowed to disagree about HOW FAR THROUGH it the
	# two are, which is the whole of the difference between soil the impact finished
	# instantly and a wood that is still going. Carried into the instance's custom data
	# below and read by `SHADER_veg_billboard.gdshader` as `INSTANCE_CUSTOM.x`. 0 off the
	# crash site, which the shader reads as "follow the bus".
	var burn := f.crater_burn(cw) * crater_burn_peak
	if cw > 0.0:
		var clear := smoothstep(maxf(crater_veg_keep - crater_veg_band, 0.0),
				crater_veg_keep, cw)
		if clear > 0.0 and _rand(hx, 7) < clear * crater_clearing:
			return {"valid": false}
	# THE POD'S DIVOT CLEARS AND DOES NOT BURN, which is the whole difference
	# between the two impacts as far as this function is concerned. Same roll on
	# the same kind of weight — a plant standing where the ground was ploughed
	# off is the failure either way — and then it stops: `burn` above is left
	# exactly where the crash site put it, which off a crash site is zero, and
	# the shader reads zero as "follow the time-of-day bus". A pod that came down
	# under a chute does not set a wood alight.
	#
	# ITS OWN LANE ON THE HASH (8, not 7). Sharing the crater's would mean a cell
	# that survived one clearing survived the other, which costs nothing today —
	# `divot_crater_clearance` keeps them 360 m apart at the least — and would silently
	# correlate the two the moment anyone shortened it.
	var dw := clampf(float(s.get("divot", 0.0)), 0.0, 1.0)
	if dw > 0.0:
		var clear := smoothstep(maxf(divot_veg_keep - divot_veg_band, 0.0),
				divot_veg_keep, dw)
		if clear > 0.0 and _rand(hx, 8) < clear * divot_clearing:
			return {"valid": false}
	# THE RUIN'S CLEARING, on the divot's rule with its own weight and its own lane
	# (9) for the divot's reason: the three roll independently, so a cell that
	# survives one clearing is not thereby a cell that survives another. Nothing
	# burns here either — `burn` is left where the crash site put it, which this far
	# from the crash site is zero.
	#
	# The weight is the LEVELLING weight, not a paint: it is exactly 1 across the
	# flat core, where the tile apron and the tower stand, so a plant there is not
	# a plant thinly spread, it is one growing through a floor. See
	# `ruin_veg_keep`.
	var rw := clampf(float(s.get("ruin", 0.0)), 0.0, 1.0)
	if rw > 0.0:
		var clear := smoothstep(maxf(ruin_veg_keep - ruin_veg_band, 0.0),
				ruin_veg_keep, rw)
		if clear > 0.0 and _rand(hx, 9) < clear * ruin_clearing:
			return {"valid": false}
	# PER-INSTANCE, NOT THE WORLD-SPACE FRONT, and it is worth knowing why. The bus's
	# `veg_burn_front` is a CIRCLE — xyz origin, w radius — and the crater is an
	# ELLIPSE: elongation is 1.45, so the footprint runs ~45 m along the ship's track
	# and ~31 m across it. A circle sized to the long axis overshoots the short one by
	# about twenty metres, a third of the feature, and that reads immediately in a
	# plan view. Worse, the front ramps to FULL burn deep inside itself and to zero at
	# its own rim, so sized TO the crater it would put full burn on ground that was
	# just cleared and leave the survivors barely scorched — a failure that looks like
	# the burn is broken rather than mis-sized. The weight above has none of that: it
	# is the real elliptical footprint, it was already being sampled, and it leaves
	# the bus free for an island-wide fire.
	#
	# WHAT IT COSTS is MultiMesh custom data: `use_custom_data` on, `_STRIDE` 12 -> 16,
	# +33% on the instance buffers and on the re-pack this file works hard to keep
	# cheap. No extra field sampling — the sample was already being taken.
	#
	# THE +33% IS REAL IN MEMORY AND IS NOT MEASURABLE IN TIME, which is worth knowing
	# before anyone optimises the re-pack on its account. Two pairs of
	# `PROBE_scatter_cost.gd` runs either side of the change, parked in inland rough
	# well away from the crash site: grass unchanged to the centisecond (0.68 / 0.43
	# ms), trees 3.12 -> 3.19 ms cached in one pair and 3.79 -> 3.69 in the other. The
	# wider stride comes out FASTER in half the runs, which is the honest reading —
	# copying a third more floats disappears into the variance of everything else a
	# scan does. What does move is 78.6k plants at 4.80 MB against 3.60 MB, plus the
	# resident tufts: about +1.5 MB CPU-side and the same again on the GPU. See
	# `PROBE_veg_census.gd`, which costs instances at this stride.
	#
	# TWO THINGS THAT ARE GONE AND MUST NOT BE REBUILT. This paragraph named
	# `MAT_*_burnt` and `MAT_*_stump` when it was written; those eight pinned
	# materials were deleted in 2b41a13 — and no material can express a burn that
	# varies WITHIN one multimesh at any number of copies, which is exactly what the
	# ring is. So was the burn's ASH LOSS erosion, which discarded texels as the flame
	# passed and produced a sparse moth-eaten plant with daylight through it — wrong
	# at every distance and worse the closer you got. If the ring ever reads as thin
	# or decayed, that is the failure to check for, and the fix is never to punch
	# holes in the sprite.

	var forest: float = clampf(s.get("forest", 0.0), 0.0, 1.0)
	var d_tree := lerpf(tree_open_density, tree_forest_density, forest) * tree_clump
	var d_bush := lerpf(bush_open_density, bush_forest_density, forest) * bush_clump
	var d_fern := lerpf(fern_open_density, fern_forest_density, forest) * fern_clump

	# THE THREE CLASSES ARE CLAMPED IN PRIORITY ORDER, and this is what lets a wood
	# be full without the classes cannibalising each other. One cell grows at most
	# one plant, so the three weights are competing for the same 0..1 and their sum
	# can exceed it — at which point SOMETHING has to give, and which one is the
	# whole character of the forest floor.
	#
	# Sharing the shortfall proportionally is the obvious answer and it is the
	# wrong one: raising the understory would then thin the CANOPY, so "more ferns"
	# would quietly mean "fewer trees" and the woods would open up as you filled
	# them in. Instead each class takes its share out of what the ones above it
	# left:
	#
	#   TREES first, and never squeezed — the canopy is the forest, and it is set
	#     by `tree_forest_density` alone whatever the undergrowth does.
	#   BUSHES second, out of the floor between the trunks. Their clump noise is
	#     thresholded, so inside a thicket this takes ALL the remaining room and
	#     outside one it takes none. That is what makes a cluster thick rather
	#     than a general raising of the bush level.
	#   FERNS last, filling whatever is still empty. Being last is not a demotion,
	#     it is the definition of a ground-cover layer: set `fern_forest_density`
	#     high and ferns carpet every part of the floor that is not trunk or
	#     thicket, and thin out on their own exactly where those are dense.
	#
	# So the three numbers stop being independent probabilities once a wood
	# saturates and become a PRIORITY, which is the thing that was actually wanted
	# of them.
	d_tree = minf(d_tree, 1.0)
	d_bush = minf(d_bush, 1.0 - d_tree)
	d_fern = minf(d_fern, 1.0 - d_tree - d_bush)

	if keep > d_tree + d_bush + d_fern:
		return {"valid": false}
	var cls := CLS_TREE
	if keep >= d_tree + d_bush:
		cls = CLS_FERN
	elif keep >= d_tree:
		cls = CLS_BUSH

	# A class with no sprites configured yields a valid cell with NO sprite rather
	# than an invalid one, and the difference matters to both callers. `_build_tile`
	# skips it, so an unconfigured class leaves holes instead of quietly handing its
	# share to the classes that are configured — density is a property of the world,
	# not of which art happens to be wired up. And it lets `PROBE_veg_census.gd`
	# count what the field describes off a bare `VegScatter.new()`, with no scene,
	# no textures and no viewport.
	var span: Vector2i = _class_span[cls] if _class_span.size() == 3 else Vector2i.ZERO
	var hr: Vector2 = _class_height[cls] if _class_height.size() == 3 \
			else Vector2(1.0, 1.0)

	# THE GROUND'S SLOPE, so the sub-plants below can stand on it without each
	# costing a field sample of its own. `sample` already returned the surface
	# normal at the cell, and a first-order extrapolation off it is exact for
	# locally planar ground and good to a few centimetres over the metre or two a
	# sub-plant is displaced — against a full sample at ~0.11 ms, which is the
	# entire cost of this function. `sink` covers the residual.
	var n3: Vector3 = s.get("normal", Vector3.UP)
	var grad := Vector2.ZERO
	if absf(n3.y) > 1e-3:
		grad = Vector2(-n3.x / n3.y, -n3.z / n3.y)
	var h0: float = s["height"] - sink

	# One plant for a tree, several for the understory — see `bush_per_cell`.
	var count := 1
	if cls == CLS_BUSH:
		count = maxi(bush_per_cell, 1)
	elif cls == CLS_FERN:
		count = maxi(fern_per_cell, 1)

	var plants: Array = []
	for i in range(count):
		# A LANE PER SUB-PLANT rather than a re-hash of the cell, so sub-plant 0 is
		# bit-identical to what a one-per-cell scatter would have placed and raising
		# the count only ADDS to a stand instead of reshuffling it.
		var lane := i * 16
		var sprite := -1
		if span.y > 0:
			sprite = span.x + int(_rand(hx, 5 + lane) * float(span.y)) % span.y
		var h := lerpf(hr.x, hr.y, _rand(hx, 4 + lane))
		var wj := lerpf(width_jitter.x, width_jitter.y, _rand(hx, 6 + lane))
		# the slope's share of the sink: half the quad's width down the gradient
		var aspect := _sprite_aspect[sprite] if sprite >= 0 and sprite < _sprite_aspect.size() else 1.0
		var down := minf(0.5 * h * wj * aspect * grad.length(), h * sink_most)
		# and the clear band under the picture, so the plant itself is in
		# the ground (see `_sprite_pad`)
		var pad := _sprite_pad[sprite] if sprite >= 0 and sprite < _sprite_pad.size() else 0.0
		down += h * pad
		# Sub-plant 0 sits on the cell's own jittered point; the rest spread across
		# the cell. They read as a CLUMP at the grid scale, which is what both
		# classes using this want — a thicket and a patch of understory.
		var ox := 0.0
		var oz := 0.0
		if i > 0:
			ox = (_rand(hx, 7 + lane) - 0.5) * 0.9 * veg_grid
			oz = (_rand(hx, 8 + lane) - 0.5) * 0.9 * veg_grid
		plants.append({
			"sprite": sprite,
			# Sunk in METRES, off the position rather than the pivot, so a 22 m fir
			# and a 1.3 m fern bury their bases by the same amount.
			"pos": Vector3(wx + ox, h0 - down + grad.x * ox + grad.y * oz, wz + oz),
			# Y-billboards ignore yaw, so scale is the whole basis. The quad is a
			# metre tall and the sprite's own aspect wide (see
			# `_build_multimeshes`), so X and Y both take the height and X
			# additionally takes the width jitter.
			"basis": Basis.IDENTITY.scaled(Vector3(
					h * wj, h, h)),
			# Every sub-plant of a cell shares the cell's crater burn — it is a property
			# of the ground the clump stands on. 0 off a crash site. Into
			# `INSTANCE_CUSTOM.x` via `_pack_tile`.
			"burn": burn,
		})

	# THE RUIN DOOR'S LANE — see `ruin_lane_clear`. After the clump is laid out, so
	# what stands is exactly the clump that would have grown, less what is on the
	# line. `rw` is nonzero only inside a ruin's footprint, and there the sample has
	# already placed that island's ruins, so this reads them rather than placing them
	# — the NEAREST, whose footprint this is (`IslandField.ruin_near`).
	if rw > 0.0 and ruin_lane_clear > 0.0:
		var site: IslandField.RuinSite = f.ruin_near(s.get("island"), wx, wz)
		if site != null:
			var kept: Array = []
			for p in plants:
				var pos: Vector3 = p["pos"]
				var d := Vector2(pos.x, pos.z) - site.center
				if d.dot(site.heading) <= 0.0 or absf(d.cross(site.heading)) >= ruin_lane_clear:
					kept.append(p)
			if kept.is_empty():
				return {"valid": false}
			plants = kept

	return {"valid": true, "class": cls, "plants": plants}


# ---- deterministic hashing (no engine RNG, so revisit/rebase stable) ----------
# Identical to `SCRIPT_grass_scatter.gd`'s, salted differently, so the two scatters draw
# from the same construction without correlating: a cell that grows a fir is not
# thereby a cell that grows grass.

static func _hash(a: int, b: int, salt: int) -> int:
	var h := (a * 73856093) ^ (b * 19349663) ^ (salt * 83492791)
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return h & 0x7fffffff


static func _rand(base: int, lane: int) -> float:
	var h := _hash(base, lane * 2654435761, 0x9E3779B9)
	return float(h % 1000003) / 1000003.0


# Smooth value noise on a coarse sub-lattice of the plant grid. `salt` is what
# gives each class its own independent field — without it the bushes would clump
# exactly where the firs do and the undergrowth would read as a texture on the
# canopy rather than as its own layer.
func _value_noise(cell: Vector2i, salt: int) -> float:
	var scale := 6
	var gx := floori(float(cell.x) / float(scale))
	var gz := floori(float(cell.y) / float(scale))
	var fx := float(posmod(cell.x, scale)) / float(scale)
	var fz := float(posmod(cell.y, scale)) / float(scale)
	var v00 := _rand(_hash(gx, gz, salt), 7)
	var v10 := _rand(_hash(gx + 1, gz, salt), 7)
	var v01 := _rand(_hash(gx, gz + 1, salt), 7)
	var v11 := _rand(_hash(gx + 1, gz + 1, salt), 7)
	var sx := fx * fx * (3.0 - 2.0 * fx)
	var sz := fz * fz * (3.0 - 2.0 * fz)
	return lerpf(lerpf(v00, v10, sx), lerpf(v01, v11, sx), sz)
