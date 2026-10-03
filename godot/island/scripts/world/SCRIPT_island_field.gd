class_name IslandField
extends Resource

# The world, as a set of PURE FUNCTIONS of logical world XZ. Nothing here is
# stored, streamed or mutated: fly away and back and you get the same terrain,
# because every value is derived from `world_seed` plus the coordinates you ask
# about. That is the same no-storage contract `SCRIPT_infinite_islands.gd` already uses,
# and it's what lets the mesher, the collision builder and gameplay code all
# agree about the world without sharing any state.
#
# THREE NESTED SCALES of the same construction are layered on top of each other.
# Each one is "a disc (or capsule) plus a noise wobble on its boundary", and each
# lives inside the one above it:
#
#   1. A LANDMASS field -- a lattice of discrete island discs, one per cell,
#      with jittered centres and radii, softened by a coastline noise. This is
#      the "scaled up, high contrast" layer: it is signed, positive on land,
#      negative over the void, and its zero-crossing IS the coastline the mesher
#      contours against. Discs rather than thresholded fBm because fBm gives
#      connected continents with filament bridges, and the whole premise here is
#      islands that are genuinely separate.
#
#   2. A ZONE field -- flattened regions carved INSIDE each island. Golf holes
#      are capsules swept from a tee to a pin; build pads are discs. Both come
#      from one `Zone` type and one mask, wobbled by `_zone_noise` so their edges
#      are lobed rather than geometric. Zones are placed by seeded rejection
#      sampling, which is what makes them ENUMERABLE and LABELLABLE: a threshold
#      on blob noise gives you blobs, but you cannot name the third one without
#      a raster connected-component pass, and naming them is the whole point.
#
#   3. A TERRAIN field -- a mixture of noises (rolling fBm + ridged spines +
#      micro detail) faded in from the coastline so land rises out of its own
#      edge instead of being sliced off mid-cliff, and scaled AWAY inside zones
#      so hills only ever occupy the ground between them. The hill term is
#      SPARSIFIED (see `hill_sparsity`): most of the wild ground is dead flat and
#      the relief budget is spent on a few tall, broad hills instead of on a
#      uniform swell.
#
#   4. A SAND-TRAP mask cutting bunkers into flat ground, biased hard into golf
#      zones so a trap reads as part of a hole rather than as weather.
#
#   5. A FOREST mask over the wild ground, which both thickens the tree scatter
#      and turns the surface under it to needle litter.
#
# Plus a splat classifier that turns slope + curvature + sand + forest + zone
# membership into the four surface weights the terrain shader blends.
#
# WHY ZONES ARE NOT JUST "FLATTER TERRAIN". Every zone carries an identity --
# `Hole.id` is `"cellX:cellZ:n"`, derived from the world seed and nothing else,
# so hole 3 of the island two cells north is the same hole with the same tee,
# pin and par whether you visit it now or after flying a thousand kilometres
# away and back. That is what makes the golf infinite without storing anything.
#
# THREADING: `get_noise_2d` is sampled from mesher worker threads, so each
# thread gets its own copy via `clone()`. Never share one instance across
# threads -- the per-cell island cache below is not guarded. Zones are built
# lazily onto their `Island` and inherit exactly the same rule.

const COAST_EPSILON := 0.02   ## Safety slack when deciding which islands can reach a region.

## Where the canopy starts thinning, as a fraction of `forest_max_slope`.
##
## Shared with the splat's rock ramp when `rock_follows_veg` is on, which is the
## whole reason it is a named constant instead of the literal it used to be
## inside `forest_at`: rock has to fade in over exactly the band the trees fade
## out over, and two copies of 0.7 in two functions is a thing that drifts.
const FOREST_SLOPE_KNEE := 0.7

## Zone kinds. `ZONE_ROUGH` is not a zone -- it is what `zone_at` reports for
## ground that belongs to none, i.e. the hills and the coastal fringe.
const ZONE_ROUGH := -1
const ZONE_GOLF := 0
const ZONE_BUILD := 1
## A graded track joining two other zones. Same capsule, three differences: it is
## narrow, its apron is its own (a path with a fairway's 75 m bank would be a
## motorway earthwork), and its shelf RAMPS from one end's altitude to the
## other's instead of being level. See `_place_paths`.
const ZONE_PATH := 2


# One island disc. `base_y` is the altitude its coastline sits at, so islands
# float at different heights; `peak` scales its terrain relief.
#
# `zones` and `holes` are built lazily by `zones_for()` and cached here, so the
# rejection sampler that places them runs once per island per field instance
# rather than once per query.
class Island extends RefCounted:
	var center := Vector2.ZERO
	var radius := 1.0
	var base_y := 0.0
	var peak := 1.0
	var cell := Vector2i.ZERO
	var is_hub := false
	var zones = null    ## Array[Zone], or null until built.
	var holes = null    ## Array[Hole], or null until built.
	## The golf config narrowed to this island's lattice cell, or null until
	## built. Read through `golf_config_for`, and cached here for the reason the
	## zones above are: the narrowing is a scan of every marker in the world and
	## the answer is the same for the life of the island.
	var golf = null     ## GolfConfig, or null until built.
	## The crash site, or null for an island that carries none. Read through
	## `crater_for` — `null` here is ambiguous until `crater_built` is set, since
	## "no crater" and "not looked yet" are different answers.
	var crater = null   ## Crater, or null.
	var crater_built := false
	## Where the escape pod came down, or null for an island that carries none.
	## Read through `divot_for`, and built on the same "null is ambiguous" rule
	## the crater above is.
	var divot = null    ## Divot, or null.
	var divot_built := false
	## The ruin entrance's clearing, or null for an island that carries none —
	## which is every island in a field with `ruin_enabled` off. Read through
	## `ruin_for`, on the same "null is ambiguous" rule as the two above. On an
	## island with a RING of entrances this is the first of them; `ruins` below
	## holds every one.
	var ruin = null     ## RuinSite, or null.
	## Every entrance's clearing, in placement order: none, the one above, or the
	## whole ring (`ruin_ring_count`). Built with it and read through `ruins_for`.
	var ruins: Array = []
	var ruin_built := false


# The crash site: where the player's ship came down. One per island at most, and
# the reason the whole feature is not simply a large bunker.
#
# A CRATER IS NOT A DISC, it is an ellipse with a direction. A vertical impact
# digs a circle; a ship arriving on a trajectory ploughs a gouge, deeper and
# walled at the far end, ramped where it first touched, with everything it
# displaced piled in front of it. `heading` is what carries that, and it is the
# difference between scenery and a thing a player can stand on the rim of and
# read: the ship came from over there.
class Crater extends RefCounted:
	var center := Vector2.ZERO
	var radius := 1.0            ## Rim radius ACROSS the impact line, in metres.
	var heading := Vector2.RIGHT ## Unit vector, the ship's direction of travel.
	## Radius past which the crater moves and paints nothing, in metres, along
	## the LONG axis — so a single distance test against this is conservative on
	## every bearing. Every early-out in `crater_at` and `crater_near` uses it.
	var outer := 1.0
	## `base_height` at the crater's own centre — the DATUM the floor is pinned to.
	##
	## WITHOUT IT THE FLOOR IS FLAT AND THE GROUND IS NOT. The bowl term is pinned
	## at exactly 1 inside `crater_floor_frac`, so the LIFT across the floor is a
	## constant `-crater_depth` to the last decimal; what was not constant was what
	## it was added to. The crater is stamped on wild ground, and the island's own
	## hills go on rising underneath it, so a floor with a perfectly flat lift came
	## out following the hillside — measured at 0.86 m of fall across the shipped
	## floor, on ground the wreck has to sit level on. Storing the datum here rather
	## than deriving it per sample is what makes the pin free: it is one number per
	## crater, taken once when the crater is placed.
	var floor_base_y := 0.0


# Where the ESCAPE POD came down, which is a different kind of event from the
# ship and therefore a different kind of ground.
#
# THE SHIP EXPLODED; THE POD LANDED BADLY. That is the whole design brief and
# every difference below falls out of it. A crater is an excavation with a rim
# thrown up all the way round it, a fused floor and a burnt collar; a pod under
# a chute comes down heavy, digs a shallow trough, skids, and stops. What it
# leaves is a DENT — no ejecta ring, no char, no molten core, no fire — with the
# only real relief at the end it stopped at.
#
# ONE SIDE IS TALLER THAN THE OTHER, AND THAT IS THE FEATURE. The pod has to end
# up leaning, and a pod leaning on nothing is a pod that fell over. So the far
# end of the trough is a BANK: ground piled and scarped into a face the pod is
# resting against, standing above the surrounding ground rather than merely
# level with it. The entry end has no lip at all — it is open, feathering out
# along the skid the way the ground it ploughed through actually would. Read
# from the air the dent is a comma, not a ring.
#
# IT IS AIMED UPHILL. `_place_divot` takes the heading from the local gradient
# rather than from the shore, so the pod ran INTO rising ground and the bank it
# is against is a scarp cut in a hillside rather than a mound heaped on a plain.
# That is the difference between a bank the world explains and one it does not,
# and it costs four height samples once per island.
#
# `heading` is the pod's direction of travel, so `+heading` from the centre is
# the bank and `-heading` is the open skid. Everything downstream reads the
# asymmetry off that one vector; nothing else needs to know which end is which.
class Divot extends RefCounted:
	var center := Vector2.ZERO
	var radius := 1.0            ## Trough radius ACROSS the skid, in metres.
	var heading := Vector2.RIGHT ## Unit vector, the pod's direction of travel.
	## Radius past which the divot moves and paints nothing, in metres, along the
	## LONG axis — so a single distance test against it is conservative on every
	## bearing, exactly as `Crater.outer` is.
	var outer := 1.0
	## `base_height` at the divot's own centre — the DATUM the trough floor is
	## pinned to, for the reason `Crater.floor_base_y` records and one more.
	##
	## The crater pins its floor so a 15 m hull does not stand with a corner in
	## the air. The pod is 3 m across and would not care about the 0.1 m the
	## hillside moves under it — but the BANK does. The pod is placed by lerping
	## along the heading until the ground rises to meet it, and a floor that
	## follows the hill moves the height the bank is measured from, so the lean
	## angle drifts with the slope the divot happened to land on. Pinned, the
	## bank's face is the same face on every seed.
	var floor_base_y := 0.0
	## World Y of the floor itself — the datum with the trough's own depth taken
	## out of it. This is what the pod stands on, and it is stored rather than
	## re-derived so the placer and the mesher cannot disagree about it by a
	## noise fetch.
	var floor_y := 0.0


# The clearing the RUIN ENTRANCE stands in: a disc of ground levelled to one
# plane, with the hillside easing back to its own shape around it.
#
# THE MODEL SAYS WHERE THE GROUND IS, AND THIS IS THE FIELD AGREEING WITH IT.
# `models/MODEL_ruin_entrance_type1.glb` carries a flat 48-segment disc called
# `CLAUDE__groundIntersectionPlaneAndTerrainSlopeMask`, drawn by the person who
# modelled the ruin as a note: its HEIGHT is where the ruin meets the ground and
# its RADIUS is the patch of ground that has to be flat for the tile apron not to
# be clipped by the hill it is standing on. This is that disc, transferred to the
# island — `radius` is the disc's, `floor_y` is where its plane lands in the world.
#
# IT IS NOT AN IMPACT AND IT IS NOT A ZONE, and the difference is what decides
# where it is applied. The crater and the divot are FEATURES — events stamped on
# top of the landform, which the splat classifies against the ground they were cut
# into. A clearing somebody levelled is the LANDFORM: the slope under it really is
# zero, so the forest, the bunkers, the rock rule and the shading all have to read
# it as flat ground, the way they read a build pad. So `ruin_at` is folded in where
# the zones are — into the base height every neighbour and every normal is taken
# from — and never into `surface_height` with the impacts. See `sample`.
#
# A BUILD PAD WAS THE OBVIOUS VEHICLE AND IT IS THE WRONG ONE, for three reasons
# that are each enough. A pad's shelf is not flat: it carries `green_undulation`,
# half a metre of contour, under an apron that stands 0.39 m proud. A pad is placed
# by the course's rejection sampler, so one appended for the ruin would either
# reshuffle every pad and hole after it or sit outside the sampler's separation
# guarantees. And a pad is a promise — "build here" — that `sample` makes to the
# player through `buildable`, on ground that has a ruin standing on it.
#
# `heading` is the way the DOOR faces: from the ruin toward the player start it
# was placed from, or on a ring toward the island's centre. The prefab's door is
# on its +Z, so `atan2(heading.x, heading.y)` is the whole of its yaw.
class RuinSite extends RefCounted:
	var center := Vector2.ZERO
	## Unit XZ vector the door faces — toward `anchor`.
	var heading := Vector2.DOWN
	## Radius of the dead-flat core, in metres — the mask disc's, copied off the
	## field when the site was placed.
	var radius := 1.0
	## Radius past which the clearing moves nothing: the core plus the slope band.
	## Every early-out tests this, exactly as `Divot.outer` is tested.
	var outer := 1.0
	## World Y of the flat core — the ground intersection plane, and so the height
	## the prefab's origin is stood at. The area-weighted MEAN of the ground the
	## disc replaces, so the levelling cuts as much as it fills. See `_ruin_survey`.
	var floor_y := 0.0
	## The player start the site was chosen from: the divot's centre. On a ring,
	## the island's centre, which every door there faces.
	var anchor := Vector2.ZERO
	## The most the levelling moved any ground under the footprint, in metres —
	## the core and the band both. Kept because it is the number
	## `ruin_earthwork_max` was checked against and a probe wants to print it.
	var earthwork := 0.0
	## Whether the site passed the openness gate, or is the fallback. See
	## `ruin_open_forest`. On a ring there is no gate, and this only says whether
	## the site happens to be open ground or a clearing cut out of a wood.
	var open := true
	## Which entrance this is, counting from the ring's first (`ruin_ring_spin`)
	## the way the bearings run. 0 for the single entrance near the start.
	var index := 0
	## How far the site sits off the ring along its own bearing, in metres —
	## positive outward. See `ruin_ring_slide`. 0 for the single entrance.
	var slide := 0.0


# One flattened region carved into an island.
#
# A golf hole is a CAPSULE: the set of points within `width` of the segment from
# `a` (tee) to `b` (pin). A build pad has `a == b`, so the capsule degenerates to
# a disc and one mask function serves both -- which is the whole reason the two
# features share a type instead of being two parallel systems.
#
# Capsules rather than circles for golf because a circular clearing reads as a
# green, not as a hole you play down: the tee and the pin have to be far apart
# and the ground between them has to be the thing that is flat. Taking the axis
# as the definition means the tee and pin fall out of the geometry for free,
# with no second placement pass that could put a pin on a slope.
class Zone extends RefCounted:
	var a := Vector2.ZERO
	var b := Vector2.ZERO
	var width := 1.0        ## Half-width of the capsule, in metres.
	var kind := ZONE_GOLF
	var index := 0          ## 1-based within its island, counted per kind.
	var lift := 0.0         ## Shelf altitude at `a`, relative to the island's `base_y`.
	## Shelf altitude at `b`. Equal to `lift` for a LEVEL zone -- a hole or a pad
	## is a shelf, and a shelf that sloped would be a ramp you cannot putt on or
	## build on. Only paths set it apart, which is what turns their capsule from a
	## flat cut into a graded track that climbs with the ground.
	var lift_b := 0.0
	## Bank width outside the wobbled boundary, in metres. Per zone rather than
	## global because the apron sets the SLOPE of the bank, and a path 4 m wide
	## does not want the same 75 m earthwork a 40 m fairway does.
	var apron := 50.0
	## Dead-level collar outside the wobbled boundary, in metres, BEFORE the apron
	## starts ramping. Golf only -- see `IslandField.zone_skirt`. Nothing to do
	## with `chunk_skirt_depth`, which is the vertical curtain the mesher hangs off
	## a chunk's edges to hide LOD seams.
	var skirt := 0.0
	## The ELBOW of a dogleg, and `bent` is whether there is one. A bent zone's
	## axis is the two-segment polyline a -> m -> b instead of the single segment
	## a -> b; everything else about it is unchanged, because everything else is
	## expressed through `axis_distance`.
	##
	## Only golf holes bend. A build pad is a degenerate capsule and a path is
	## already a chain of two capsules meeting at a waypoint, so neither has any
	## use for it.
	var m := Vector2.ZERO
	var bent := false
	## A SQUARE build pad (`IslandField.square_pads`, at the user's request for
	## CANDY LAND's towns): `width` is its half-side, `rot` the way its sides
	## run, and a cross of streets `street` metres either side of its two
	## middle lines splits it into four quadrants.
	var square := false
	var rot := 0.0
	var street := 0.0

	func length() -> float:
		return a.distance_to(m) + m.distance_to(b) if bent else a.distance_to(b)

	## The axis as a list of segments — one for a straight zone, two for a dogleg.
	## Placement tests iterate this rather than assuming a single segment.
	func segments() -> Array:
		return [[a, m], [m, b]] if bent else [[a, b]]

	## Distance from a point to the capsule's axis. Subtracting `width` from this
	## gives the signed distance to the zone's (un-wobbled) boundary.
	func axis_distance(p: Vector2) -> float:
		if square:
			# (the larger of the two distances along its sides, so `width` out
			# from the middle is its square edge, not a circle)
			var q := (p - a).rotated(-rot)
			return maxf(absf(q.x), absf(q.y))
		if bent:
			return minf(_seg_distance(p, a, m), _seg_distance(p, m, b))
		return _seg_distance(p, a, b)

	static func _seg_distance(p: Vector2, s0: Vector2, s1: Vector2) -> float:
		var ab := s1 - s0
		var d2 := ab.length_squared()
		if d2 < 1e-9:
			return p.distance_to(s0)
		return p.distance_to(s0 + ab * clampf((p - s0).dot(ab) / d2, 0.0, 1.0))

	## Shelf altitude under a point: `lift` at the `a` end, `lift_b` at the `b`
	## end, linear in the axis parameter between them and flat past either cap.
	## Short-circuits for the level case, which is every zone but a path — and a
	## path is never bent, so the straight-axis parameterisation below is always
	## the right one for the case that reaches it.
	## Whether a point is on one of a square pad's two cross streets.
	func on_street(p: Vector2) -> bool:
		if not square or street <= 0.0:
			return false
		var q := (p - a).rotated(-rot)
		return absf(q.x) <= street or absf(q.y) <= street

	func lift_at(p: Vector2) -> float:
		if is_equal_approx(lift, lift_b):
			return lift
		var ab := b - a
		var d2 := ab.length_squared()
		if d2 < 1e-9:
			return lift
		return lerpf(lift, lift_b, clampf((p - a).dot(ab) / d2, 0.0, 1.0))


# The label attached to a `ZONE_GOLF` zone: everything gameplay needs to present
# it as a hole you can walk up to and play.
#
# `id` is stable for the life of `world_seed` and is derived from the island's
# lattice cell plus the hole's index within it. Nothing is stored, so the id is
# safe to write into a scorecard, a save file or a leaderboard.
class Hole extends RefCounted:
	var id := ""                ## "cellX:cellZ:n" -- stable, storage-free.
	var index := 0              ## 1-based within its island.
	var cell := Vector2i.ZERO
	var tee := Vector2.ZERO     ## Logical world XZ.
	var pin := Vector2.ZERO
	var width := 1.0            ## Fairway half-width, in metres.
	var length := 0.0           ## Tee to pin, in metres.
	var par := 3
	## Which of `GolfConfig`'s three levels produced `par` -- one of its
	## `PAR_FROM_*` constants. Carried on the hole rather than recomputed because
	## the only place the question is cheap to answer is the place the answer was
	## made, and a scorecard that cannot say "this 7 is the default, not a rule"
	## is a scorecard that makes the default look like a bug.
	var par_source := GolfConfig.PAR_FROM_LENGTH
	## The dogleg's ELBOW, and whether there is one — mirrored off the `Zone` this
	## hole was labelled from, in the same logical XZ frame as `tee` and `pin`.
	##
	## `length` has always measured the bent axis (`Zone.length()` sums a -> m -> b),
	## so a caller reading tee, pin and length together was already being told about
	## a bend it had no way to locate. Anything that reconstructs the hole's SHAPE
	## rather than just its endpoints needs the elbow: `SCRIPT_golf_wall.gd` builds a
	## two-segment capsule from it, and a wall drawn tee-to-pin instead would cut
	## the corner off every dogleg on the island.
	var bend := Vector2.ZERO
	var bent := false


@export var world_seed := 1337

@export_group("Hub islands")
## Large islands the world is composed around, with satellites scattering out
## from them. A hub overrides the satellite its lattice cell would otherwise have
## rolled, so streaming, meshing and point queries all stay on one uniform "ask
## the lattice" path.
##
## Hubs RECUR: they sit on a coarse sub-lattice of the island lattice, phase-
## aligned so that `hub_center` is always one of them. That is what makes the
## golf infinite while keeping courses to hub islands only — fly far enough in
## any direction and another course island comes over the horizon.
@export var hub_enabled := true
## Anchor hub position. Every other hub is this one translated by a whole number
## of `hub_lattice` cells, so the field stays a pure function of the lattice.
@export var hub_center := Vector2.ZERO
## Island-lattice cells between hubs, on each axis. At the default spacing of
## 900 m this puts a hub every ~10.8 km — far enough apart that you never see two
## at once, close enough to fly between.
##
## Must keep hubs disjoint: `hub_lattice * island_spacing` has to exceed
## `2 * hub_radius * (1 + coast_irregularity)`, for exactly the reason satellites
## must stay disjoint. `tests/TEST_island_world.gd` asserts it.
@export var hub_lattice := 12
## Radius in metres. 1250 gives a ~2.5 km landmass.
@export var hub_radius := 1250.0
## Altitude of the ANCHOR hub. Other hubs are spread around it by
## `hub_base_spread` so the world does not read as one flat plane of courses.
@export var hub_base_y := 0.0
@export var hub_peak := 1.0
## Altitude spread of non-anchor hubs about `hub_base_y`, in metres.
##
## Deliberately tighter than `vertical_spread`: a hub is 2.5 km across and its
## whole surface would sit in the haze if it dropped as far as a satellite may.
## This is also the natural place to hang per-hub variation later — see the
## "many hubs, different biomes" note in `docs/DOC_procedural_island_world.md`.
@export var hub_base_spread := 90.0
## Clear void kept between any hub's coastline and any satellite's, in metres.
## Satellites that would land inside this are dropped outright.
@export var hub_clearance := 240.0

@export_group("Satellites")
## Island lattice cell size. One satellite candidate per cell.
@export var island_spacing := 900.0
## Satellite radius at the hub's rim, falling to `satellite_radius_far` by
## `satellite_reach`. Clamped against `island_spacing` -- see `max_radius()`.
@export var satellite_radius_near := 250.0
@export var satellite_radius_far := 85.0
## Fraction of lattice cells holding a satellite, near the hub and far from it.
@export_range(0.0, 1.0) var satellite_density_near := 0.80
@export_range(0.0, 1.0) var satellite_density_far := 0.14
## Distance out from the hub's rim over which satellites shrink and thin, in
## metres. Past this they stay at the `_far` values rather than stopping, so the
## world still streams forever instead of ending at a wall.
@export var satellite_reach := 4500.0

@export_group("Landmass")
## Coastline wobble, as a fraction of island radius. Pushes the shoreline in and
## out so islands aren't discs. Kept small enough that two islands still can't meet.
@export_range(0.0, 0.4) var coast_irregularity := 0.15
## Feature size of that coastline wobble, in metres.
@export var coast_noise_scale := 130.0
## Jagged coast mode. When on, the wobble is a function of ANGLE around the island
## centre only, not of 2D position — so the shore radius varies with bearing while
## the land stays the star-shaped set {distance <= R(angle)}. That set is
## simply-connected by construction: along any ray out from the centre the mask
## `1 - d/R + wobble(angle)*coast_irregularity` is strictly decreasing in `d`, so it
## crosses zero exactly once. The result is a JAGGED shore with NO detached specks
## and NO interior void holes, however large `coast_irregularity` is pushed. Off
## restores the stock 2D-noise wobble (which can pinch off islets and open lagoons).
@export var coast_jagged := false
## Angular feature spacing of the jagged shore, as the sampling radius (in noise
## input units) of the circle the coast noise is read around. Larger = more, finer
## serrations round the rim; smaller = a few broad lobes. Only used when
## `coast_jagged`. The 3-octave coast noise adds fractal roughness on top.
@export var coast_jag_scale := 520.0
## Altitude band the islands float within, i.e. base heights span +/- this.
## Must sit ABOVE the shader's `fog_top`, or the lowest islands generate inside
## the fog and are never visible. See `cliff_depth` for the other half of that
## relationship.
@export var vertical_spread := 180.0

@export_group("Terrain")
## How far inland (in mask units, 0 at coast → 1 at island centre) terrain takes
## to reach full height. Small values give abrupt cliff-edge plateaus.
@export_range(0.02, 1.0) var shore_width := 0.22
@export var hill_height := 24.0
@export var hill_scale := 640.0
## OCTAVES ARE THE SMOOTHNESS DIAL, and the one to reach for before the
## heights. fBm at four octaves carries detail down to `hill_scale` / 8 -- 80 m
## features on a 640 m swell -- and that fine octave is what makes a hillside
## read as crumpled rather than as a hill. It also costs the most per sample,
## since every octave is another noise fetch at every vertex.
##
## Two octaves keeps the broad shape and the asymmetry that stops a hill
## looking like a cosine, and drops the crumple. Three is the most this should
## ever be; one is a perfectly smooth blob.
@export_range(1, 6) var hill_octaves := 2
## SPARSITY: the hill noise, remapped to 0..1, below which the ground is dead
## flat. Raw fBm is a uniform swell — every square metre is some way up or down
## some slope, so there is no flat ground anywhere and the relief budget is spent
## everywhere at once. Clipping the bottom of the range off gives the opposite
## composition: most of the wild ground is level, and the full `hill_height` is
## spent on the minority of it that does rise.
##
## This is what lets `hill_height` go up and the world get flatter at the same
## time, and it is why raising `hill_scale` alone was never enough — a
## lower-frequency swell is still a swell.
##
## It is a strong dial and it overshoots easily: at 0.5 fully 61% of the wild
## ground came out dead level, which reads as plains with knolls dropped on them
## rather than as landscape. 0.32 keeps the flats as a minority feature.
@export_range(0.0, 0.95) var hill_sparsity := 0.32
## Noise span, in the same remapped 0..1 units, over which a hill climbs from the
## flat to its full height. Narrow gives abrupt, distinct hills; wide gives long
## shoulders. Multiplied out against `hill_scale` this is the thing that actually
## sets a hillside's gradient — it is THE gentleness dial, and the one to move
## before touching `hill_height`, because widening it costs no altitude.
##
## At 0.22 the whole rise was compressed into ~47 m of run and the flanks peaked
## around slope 0.31; at 0.40 it is ~86 m and they peak near 0.14. Same hills,
## walkable.
@export_range(0.05, 0.9) var hill_ramp := 0.62
## RIDGED noise is creased by construction -- it is |noise| folded, so every
## zero crossing of the source becomes a sharp spine. That is the whole reason
## it reads as mountains, and the whole reason it fights `hill_ramp`: no
## widening of the hill shoulders smooths a crease that is added on top of it.
## So on a course island it is kept as a trace of structure rather than as
## terrain, and at two octaves rather than four.
@export var ridge_height := 5.0
@export var ridge_scale := 700.0
@export_range(1, 6) var ridge_octaves := 2
## How completely the ridge term is confined to the hills. At 1.0 spines exist
## only where the hill mask does, so the flats between hills stay flat; at 0.0
## ridged noise covers the whole island the way it used to and quietly undoes
## `hill_sparsity`, because a 20 m spine field on "flat" ground is not flat.
@export_range(0.0, 1.0) var ridge_on_hills := 0.85
@export var micro_height := 0.6
@export var micro_scale := 34.0

@export_group("Golf zones")
## Carve labelled golf holes and build pads into every island. Turning this off
## restores the pre-zone world exactly: relief is never scaled away, sand is
## never biased, and `sample()` reports every point as rough.
@export var zone_enabled := true
## Restrict golf to HUB islands. Satellites keep their hills and their build
## pads and simply carry no course, so a course reads as a destination you fly
## to rather than as something every rock in the sky happens to have.
##
## Note what this couples to: with a single hand-placed hub, this makes the world
## hold exactly one course. `hub_lattice` is the knob that makes hubs — and so
## the golf — recur forever.
@export var golf_hub_only := true
## Smallest island radius allowed to hold a course, in metres. Applies whether or
## not `golf_hub_only` is set, so turning that off gives a size-graded world
## rather than a hole on every pebble.
@export var golf_min_radius := 400.0
## Upper bound on holes per island, whatever its size. Nine is a front nine and
## is more than the hub can geometrically fit; the binding limit in practice is
## the rejection sampler running out of room.
@export var holes_max := 9
## Tee-to-pin length band, in metres. Par is derived from the result, so this is
## the knob that decides whether the world plays as real golf or as pitch-and-putt.
##
## COUPLED TO CLUB POWER. `SCRIPT_golf_controller.gd` gives the driver 65 m/s at 11
## degrees with `POWER_MULTIPLIER = 2.0`, which carries far past a 450 m hole.
## Raise these, or lower that multiplier, if a par 4 should take more than one
## swing. Nothing here reads club power -- the two are tuned by hand.
@export var hole_length_min := 180.0
@export var hole_length_max := 450.0
## Shortest hole an island is allowed to hold. An island too small to fit this
## gets no golf at all and stays wild, which is what keeps far satellites from
## all sprouting a token stub of fairway.
@export var hole_length_floor := 70.0
## Fairway half-width as a fraction of hole length, then clamped to the bounds
## below. Proportional so a long par 5 is a broad corridor and a short par 3 is
## a narrow one.
@export_range(0.02, 0.5) var hole_width_ratio := 0.11
@export var hole_width_min := 14.0
@export var hole_width_max := 40.0
## EVERY HOLE DOGLEGS. The corridor is a two-segment polyline rather than a
## straight capsule, and this is how far the second leg turns off the first, in
## degrees of DEFLECTION (0 would be straight on; 90 would be square). A hole you
## can see the pin from and hit down in one line is not a hole, it is a driving
## range, so the minimum is a real turn rather than a hint of one.
##
## The turn direction is a coin flip per hole, so a course has left and right
## doglegs rather than a spiral.
@export_range(0.0, 90.0) var dogleg_angle_min := 45.0
@export_range(0.0, 90.0) var dogleg_angle_max := 75.0
## Where the elbow sits, as a fraction of the hole's total length spent on the
## first leg. Bounded away from both ends because an elbow 10% along is not a
## dogleg, it is a crooked tee box: the corner has to be far enough from the tee
## to be a decision and far enough from the pin to leave an approach.
@export_range(0.15, 0.5) var dogleg_split_min := 0.35
@export_range(0.5, 0.85) var dogleg_split_max := 0.6
## Absolute floor on a leg, in metres. This is only a degeneracy guard — the
## PROPORTIONS are `dogleg_split_min/max`'s job, and they are the right shape for
## it: a 25 m leg on a 70 m hole is a real dogleg, while the same 25 m on a 400 m
## hole is a kink at the tee. An absolute floor large enough to catch the second
## case would refuse to place the first at all.
@export var dogleg_leg_min := 20.0
## Fraction of an island's usable area that golf should occupy. This is what
## scales hole COUNT with island size; `holes_max` only caps the top end.
@export_range(0.0, 1.0) var golf_area_fraction := 0.30
## Length at or below which a hole is a par 3, then a par 4. Anything longer is
## a par 5, up to the maker's reach -- see `GolfConfig.par5_max`.
##
## THESE TWO SEED THE BUILT-IN CONFIG AND ARE IGNORED ONCE `golf_config` IS SET.
## Par is `SCRIPT_golf_config.gd`'s job now; when no config resource is assigned
## this field builds itself a default one out of these two numbers, which is what
## keeps every `ISLANDFIELD_*.tres` already in the tree playing exactly as it did.
@export var par3_max := 230.0
@export var par4_max := 400.0
## The par system: markers, the length maker and the global default, as one
## resource. See the header of `SCRIPT_golf_config.gd` for the three levels and
## the order they are asked in.
##
## Null is not "no par system" -- it is "the default one", built from `par3_max`
## and `par4_max` above and `GolfConfig`'s own defaults for everything else. A
## field that could have no par system at all would need every caller of `par`
## to handle a hole that has none, to buy nothing.
@export var golf_config: GolfConfig = null

@export_group("Build flats")
## Flat cleared pads between the golf zones and the hills, for the player to
## build on. Same `Zone` machinery as a hole, with `a == b` so the capsule is a
## disc, and placed by the same sampler after the holes so they never overlap.
@export var build_pads_max := 14
@export var build_pad_radius_min := 30.0
@export var build_pad_radius_max := 140.0
## Cap on pad radius as a fraction of the island's placeable radius, so a pad
## sized for the hub does not swallow a satellite whole.
@export_range(0.05, 1.0) var build_pad_radius_ratio := 0.45
## Fraction of usable island area given over to build pads, scaling their count
## with island size the same way `golf_area_fraction` scales holes.
##
## Together with `hill_sparsity` this is the "more flat non-golf ground" dial.
## The two work at different scales and both are needed: sparsity makes the WILD
## ground level, this makes more of it a deliberate, named, buildable clearing.
@export_range(0.0, 1.0) var build_area_fraction := 0.30
## SQUARE TOWNS (at the user's request, CANDY LAND: "flat squares, a road
## intersection, no hills, cut out of the surrounding terrain with cliffs,
## divided into quadrants"). Every build pad a square instead of a disc,
## its sides run along the line to its nearest neighbour, its edge banked
## over only `square_apron` metres — so where the ground round it is higher
## it is a cliff — and a cross of streets `path_width` either side of its
## middle lines. Every road leaves it from the end of one of those streets,
## so a town is where the roads meet. Off by default: every other island's
## pads stay discs.
@export var square_pads := false
@export var square_apron := 1.5

@export_group("Zone shape")
## Boundary wobble as a fraction of a zone's width, which is what turns a
## geometric capsule into the lobed blob the design calls for. Kept well under
## the separation guarantee below -- see `zone_separation`.
@export_range(0.0, 0.6) var zone_irregularity := 0.25
## Feature size of that wobble, in metres. Sits between `coast_noise_scale` and
## `sand_wobble_scale` so the three nested boundaries read at three distinct
## scales instead of blurring into one texture.
@export var zone_noise_scale := 70.0
## Width of the bank around a zone, in metres, over which hill relief comes back.
##
## MEASURED IN METRES, NOT MASK UNITS, and that is the whole point: the drop from
## full hill relief to a flat shelf is tens of metres, so an apron specified as a
## fraction of zone width would be a few metres wide on a narrow par 3 and put a
## near-vertical rock wall around it. Fixing the apron in world units fixes the
## SLOPE of the bank instead, which is the thing that actually has to stay
## walkable and stay under `rock_slope_lo`.
##
## THIS SCALES WITH `hill_height`. It was 50 m against a 39 m worst-case relief;
## the sparsified hills reach ~54 m, and — since `golf_inset` recesses a fairway
## another 7 m below that — the worst-case bank is over 60 m of drop. Raise
## `hill_height` or `golf_inset` and you have to raise this, and check
## `zone_separation` after it: the gap has to stay above
## `2 * (zone_apron + zone_skirt)` or the hills between two zones never come back.
##
## PULLED IN 78 -> 55 TO PAY FOR THE WIDER COLLAR, and it cost almost nothing
## because this is a CEILING and most holes were never reaching it. The actual
## bank is `zone_apron_for(w)` = `min(this, max(zone_apron_min, w * ratio))`, and
## at ratio 2.0 with half-widths of 14..40 m that is 34..80 before the cap — so
## lowering the cap steepens only the widest fairways on the island. Measured
## across the hub by `tests/PROBE_zone_skirt.gd`, the whole bank went from mean
## slope 0.111 / worst 0.496 to 0.117 / 0.524, against a rock onset of 0.294.
##
## The pair's OUTER REACH is what `zone_separation` actually cares about, and
## that is deliberately unchanged: 78 + 16 was 94 m, 55 + 40 is 95. Two
## neighbours at the 165 m minimum overlap by 25 m instead of 23, which is the
## same trade `zone_skirt` documents and measures, one notch further along.
@export var zone_apron := 55.0
## A zone's bank as a multiple of its own half-width, capped by `zone_apron` and
## floored by `zone_apron_min`.
##
## Needed because the ceiling alone stopped fitting once it grew. A 31 m build
## pad with a 65 m bank is four times as much earthwork as pad, so most of
## what `sample()` was willing to call "a build pad" was hillside — the ground
## reported flat enough to build on averaged four times the slope of the pad's
## own dead-level core. Sizing the bank to the zone puts the clearing back in
## charge of its own footprint, and leaves the island more room for the hills and
## the paths between them.
@export_range(0.5, 4.0) var zone_apron_ratio := 2.0
## Floor under that, in metres, so a narrow par 3 does not end up ringed by a
## near-vertical wall. This is the constraint the ratio would otherwise violate,
## and the reason the apron cannot simply BE a fraction of zone width.
@export var zone_apron_min := 34.0
## Dead-level collar around every GOLF zone, in metres, between its wobbled
## boundary and the start of its apron. Zero disables it.
##
## THE APRON IS NOT ALREADY THIS. `1 - smoothstep(0, apron, sd)` leaves the zone
## at weight 1, but it starts descending immediately, so a hill crowding a hole
## gets to lean over the mown edge before the bank does anything about it.
## Measured on the hub by `tests/PROBE_zone_skirt.gd` before this existed: 8 to
## 12 m outside a fairway's boundary the ground averaged a 0.106 slope and had
## already fallen 2.3 m below the shelf, against 0.006 and dead level on the
## fairway itself. Ground still as flat as the hole reached 4 m out. With the
## collar it is 0.006 and level to the full 40, and the bank past it is the same
## bank -- mean slope 0.122 -> 0.117 -- because the ramp is TRANSLATED, not
## compressed.
##
## WIDENED 16 -> 40 M, which is the change this number exists to make cheap. The
## first 40 m outside a fairway now reads 0.002..0.007 slope and sits within
## 0.1 m of the shelf, where at 16 m it was already falling 5 m away by the
## 24..40 band. `zone_apron` came down 78 -> 55 in the same move so the pair's
## outer reach did not grow; see there for why that cost almost nothing.
##
## IT CHANGES THE LAND, NOT THE COURSE. The mown stripe, the "which hole am I on"
## answer and "can I build here" all keep reading the un-skirted weight -- see
## `zone_at`, which returns one and writes the other. Widening the flattening is
## a change to the ground; widening the grooming would be a change to the golf
## course, and a 16 m collar on a 14 m half-width par 3 would more than double
## its mown width.
##
## What DOES follow is anything gated on the terrain rather than on the zone, and
## that is the rule working rather than a leak in it: `sand_at` suppresses traps
## above `sand_max_slope`, so the few collar points that used to be too steep for
## a bunker are now flat enough for one (2.5% of them, measured). The zone weight
## scaling those traps has not moved; the ground under them has, and a bunker on
## level ground just off the fairway is where a bunker belongs. `forest_at` and
## the splat read slope the same way, which is how the collar comes out green and
## treeless instead of rocky.
##
## IT IS ALSO WHAT KEEPS THE ROCK OFF THE COURSE. `rock_follows_veg` starts
## painting rock at slope 0.294, which zone banks reach and hills mostly do not,
## so the two changes meet on exactly this ground. Same probe, same holes, with
## the new rock rule either way: without the collar, 6.0% of the ground 16 to
## 24 m outside a fairway boundary comes out bare rock. With it that band is
## 0.0%, and at 40 m so is everything out to 40 -- the rock has moved onto the
## bank past it (2.4% at 40..60, 2.5% at 60..80), where a rocky outcrop below a
## raised green is the point rather than the problem.
##
## COSTS SEPARATION, and the sum is worth checking after a change: the outer
## reach of a zone is `zone_apron + zone_skirt`, so at the shipped 55 + 40 two
## neighbouring zones at the minimum `zone_separation` of 165 m overlap by 25 m.
## That is survivable rather than accidental -- the smoothstep is almost flat by
## then, so the midpoint between two holes keeps most of its relief. It is also
## the end of the cheap range: widening the collar further means moving
## `zone_separation` (which costs holes, since `golf_area_fraction` decides how
## many fit) rather than trading against `zone_apron`, because the apron is now
## close to `zone_apron_min` and cannot fund another 20 m.
##
## Nothing to do with `chunk_skirt_depth`.
@export var zone_skirt := 40.0
## Clear ground kept between any two zones' wobbled boundaries, in metres.
##
## Two jobs. It keeps zones provably disjoint so a point is never ambiguously
## on two holes -- which needs only `2 * hole_width_max * zone_irregularity`
## (20 m at the defaults). The rest of it is the hills: set below `2 *
## zone_apron` the aprons of neighbouring zones meet and the ground between two
## holes never returns to full relief, so there is no hilly rough at all.
##
## PATHS ARE EXEMPT. They exist precisely to join zones, so they are placed after
## this test rather than subject to it — see `_place_paths`.
@export var zone_separation := 165.0
## Cap on that separation as a fraction of the island's placeable radius.
##
## Proportional for the same reason `cliff_depth_ratio` is: no fixed gap serves
## both sizes. 140 m of rough between holes is a comfortable walk on the 2.5 km
## hub and larger than a 400 m satellite can spare -- and the failure is silent
## and total, because the sampler simply rejects every candidate and the island
## comes out with a hole and no build pads at all. This is what stops a small
## island being priced out of its own flat ground.
@export_range(0.05, 1.0) var zone_separation_ratio := 0.40
## How far inland a zone must stay, in mask units.
##
## MUST EXCEED `shore_width`, or a zone lands on the shore ramp: the ramp
## multiplies the whole height expression, so a shelf sitting on it comes out
## tilted toward the sea and its `lift` is scaled by an amount that varies
## across the zone. `_zone_safe_radius()` converts this to metres against the
## worst-case coastline wobble.
@export_range(0.0, 0.9) var zone_coast_margin := 0.25
## Per-zone shelf altitude spread around the island's `base_y`, in metres, so a
## course reads as terraced rather than as one flat pan.
@export var zone_lift_spread := 9.0
## How far a GOLF shelf is recessed below the island's base altitude, in metres.
##
## The course reads as cut INTO the land rather than laid on top of it. That
## matters more than it sounds now that the hills are sparsified: relief is
## strictly non-negative, so wild ground never goes below `base_y` and a fairway
## sitting at `base_y` is merely the lowest ground rather than visibly sunken.
## Insetting it puts a rim all the way round every hole, which is what makes a
## fairway read as a fairway from the air.
##
## Build pads are deliberately NOT inset: a cleared pad is somewhere to found a
## structure, and a structure in a sump collects the hillside.
@export var golf_inset := 7.0
## THE MOWN STRIPE IS TIGHTER THAN THE FLATTENING, and these two are the gap
## between them. `zone_at` returns a weight that falls off over the whole apron —
## 75 m for a fairway — because the GROUND has to ease out over that distance or
## a hole sits in a crater. The striped lawn does not: a fairway is mown to an
## edge, and painting it across the full apron put the mower stripes over most of
## the visible island.
##
## So the grooming channel the mesher writes is this remap of the flatten weight
## rather than the weight itself. Below `golf_groom_lo` there is no lawn at all;
## by `golf_groom_hi` it is fully mown. Both live near the top of the range
## because that is where the apron's last few metres are — the corridor itself
## sits at 1.0.
##
## Raise `golf_groom_lo` to pull the lawn in tighter; close the gap between them
## for a sharper mow line, open it for a scruffier one. This changes the ALBEDO
## only. Nothing about playability, height or slope reads it.
@export_range(0.0, 1.0) var golf_groom_lo := 0.72
@export_range(0.0, 1.0) var golf_groom_hi := 0.94
## Gentle contour left on a golf zone's shelf, in metres. Without it a fairway
## is a plane and a putt has nothing to break on.
@export var green_undulation := 0.55
@export var green_scale := 42.0
## Fraction of the micro-detail noise kept inside a zone. Below 1 so groomed
## ground is visibly smoother underfoot than the rough beside it.
@export_range(0.0, 1.0) var green_micro := 0.5

## How completely a zone overrides the slope/curvature splat rules. 1.0 paints
## the core one flat surface; a little under that lets the underlying variation
## show through so the ground does not look stencilled on.
@export_range(0.0, 1.0) var fairway_grooming := 0.85
@export_range(0.0, 1.0) var pad_grooming := 0.90
## Flatten weight at or above which `sample()` will NAME the zone you are in.
##
## Blending and labelling want different answers here. Height, sand and splat all
## need the continuous weight, because a bank that snapped between hill and shelf
## would be a cliff. But "which hole am I on" is a yes/no question, and answering
## yes anywhere the weight is non-zero puts the player on hole 3 while they are
## still forty metres up the hillside above it. Below this threshold `sample()`
## reports "rough" and an empty hole id, while still reporting the true
## `flatten` for anything that wants the gradient.
##
## COUPLED TO THE APRON WIDTH AND TO ITS STEEPNESS, which is easy to miss because
## the units hide both. The weight is `1 - smoothstep(0, apron, distance_outside)`,
## so a fixed weight is a fixed FRACTION of the apron and moves in metres whenever
## the apron does — and worse, the band just outside the zone is where the
## smoothstep is STEEPEST, so it is the part of the bank most likely to be a
## slope rather than a shelf. Measured on a build pad: dead level (0.02) inside
## the boundary, 0.13 across the 0.88..0.98 band, 0.24 across 0.75..0.88. Taller
## hills and a recessed course made those numbers worse, so this came up with
## them. 0.88 is about 12 m outside the boundary at the shipped apron.
@export_range(0.0, 1.0) var zone_label_min := 0.88
## Flatten weight at or above which a build pad reports as buildable ground.
## Deliberately stricter than `zone_label_min`: you can be standing on a pad —
## and be told so — while still too far up its bank to found anything level.
@export_range(0.0, 1.0) var buildable_flatten := 0.96
## Rejection-sampler attempts per zone asked for. The sampler stops early once
## it has placed everything it wanted, so this only costs time on crowded
## islands where most candidates are rejected.
@export var zone_place_attempts := 40

@export_group("Paths")
## Join the zones on an island with graded tracks. OFF by default.
##
## Turned off after seeing them in the world: a track is 7 m of flattened ground
## plus two 9 m banks crossing every stretch of rough on the island, and at that
## width it reads as a scar rather than as a route. The machinery is intact and
## tested — flip this back on to get it — but nothing ships with it.
##
## WHY THEY EXIST. `zone_separation` deliberately leaves 190 m of un-flattened
## hill between any two zones, so with the sparsified hills every clearing on an
## island is an island of its own — you drop off a 75 m apron into the rough,
## cross a hill and climb another apron to reach the next hole. Paths are the
## connective tissue: narrow, graded, and cut with their own much tighter apron
## so they read as a track rather than as another clearing.
##
## They are the FOURTH scale of the same one construction the rest of the world
## is built from — a capsule with a wobbled boundary — with two properties none
## of the others have: they are allowed to overlap what they join (they would be
## useless otherwise), and their shelf RAMPS rather than being level.
@export var path_enabled := false
## Track half-width, in metres. Around 4-6 m reads as a footpath; much wider and
## it stops being distinguishable from a thin build pad.
@export var path_width := 3.5
## Bank width either side of a path, in metres. Much tighter than `zone_apron`
## because a path is a cutting, not a terrace: it is supposed to be visibly
## incised into the hillside it crosses.
@export var path_apron := 9.0
## Dog-leg waypoints scored per link. A path is TWO capsules, joined at a
## waypoint whose own shelf altitude is the terrain height there, so the track
## climbs with the ground instead of ploughing a straight cutting through it.
## Candidates are scored by how much earth the two halves have to move (see
## `_path_cut`) and the cheapest wins, which makes paths bend around hills for
## free, with no routing pass and nothing stored.
@export var path_waypoint_tries := 4
## How far a candidate waypoint may sit off the straight line, as a fraction of
## the link's length.
@export_range(0.0, 1.0) var path_waypoint_spread := 0.32
## Samples per half-link used to score a candidate. Purely a cost/quality dial on
## the routing; it changes the layout, so it is part of the seed's meaning.
@export var path_grade_samples := 5
## How completely a path grooms to bare earth. Same channel as a build pad — see
## `splat_weights` — and told apart from one in the shader by UV2.
@export_range(0.0, 1.0) var path_grooming := 0.85

@export_group("Forest")
## Dense-tree regions with their own ground surface.
##
## The mask is read by TWO consumers and that is the whole point of putting it
## here rather than in the scatter: `SCRIPT_veg_scatter.gd` uses it to decide how
## thickly to plant, and the splat uses it to turn the ground under the canopy to
## needle litter. One noise, so the trees and the floor they stand on can never
## disagree about where the wood is.
@export var forest_enabled := true
## Blob size of a forest region, in metres. Sits above `hill_scale` so a wood
## covers several hills rather than tracking them.
@export var forest_scale := 520.0
## Fraction of eligible wild ground that is forest.
@export_range(0.0, 1.0) var forest_coverage := 0.38
## How sharply a wood's edge cuts in, in noise units.
##
## THIS IS A THRESHOLD, and the narrow default is the point. `forest_coverage`
## picks an isovalue on the noise and this is the width of the ramp across it, so
## small values make `forest_at` very nearly binary: inside the contour is wood,
## outside is open ground, with a metre or two of transition rather than a
## hundred-metre gradient. That is what turns a haze of trees thinning gently
## outward into a wood with an EDGE you can stand at.
##
## Not zero, and it should not be: `SCRIPT_veg_scatter.gd` interpolates its keep
## probability across this band, so a step function would put a hard line of
## trees on the ground. A couple of tuft-widths of ramp reads as a treeline.
@export_range(0.01, 0.6) var forest_edge := 0.06
## Forest thins out above this slope (0 flat .. 1 vertical), so a wood does not
## carpet a cliff face.
##
## THE VEGETATION CEILING FOR THE WHOLE WORLD, not just for trees, and that is
## what `rock_follows_veg` reads it as: `grass_scatter.max_slope` is set to match
## it, and above it nothing at all is planted. Move it and the rock faces move
## with it. `tests/TEST_island_world.gd` asserts the two stay equal.
@export_range(0.0, 1.0) var forest_max_slope := 0.42
## Forest stays this far inland of the coastline, in mask units, so the canopy
## never hangs over the cliff edge.
@export_range(0.0, 1.0) var forest_coast_margin := 0.14
## Fraction of the grass weight that becomes soil under a full canopy — the
## needle-litter floor, in the four channels the textured splat shader already
## has. Kept under 0.5 so grass stays the DOMINANT surface in a wood: the tree
## scatter and `sample()["surface"]` both read the dominant weight, and a forest
## that classified as bare soil would be a forest that refuses to grow trees.
@export_range(0.0, 0.5) var forest_litter := 0.34

@export_group("Sand traps")
@export var sand_enabled := true
## Mean distance between trap centres, in metres. THIS IS THE COUNT DIAL.
##
## Trap centres are the feature points of a jittered grid with this spacing, so
## the number of traps is the fairway's area divided by `sand_spacing` squared,
## less whatever the slope, coast and tee/pin rules veto. Halving this quadruples
## the traps. It does NOT change their size -- that is `sand_radius`, and the two
## being independent is the entire reason for this model.
##
## ALSO SETS WHETHER EVERY HOLE GETS A BUNKER, which is not obvious and is not
## monotone. The grid is laid over the WORLD, not over the course, so a hole
## whose flat core is smaller than one grid cell only gets a trap if the lattice
## happens to fall inside it -- and measured, spacing 96 covers FEWER holes than
## 108 does. 108 is tuned to cover every hole on both shipped presets; it is not
## a construction that guarantees it. Re-measure after any change to the hole
## layout, the island radius or the seed. `scripts/SCRIPT_measure_sand.gd` reports it.
@export var sand_spacing := 108.0
## Trap radius, in metres. THIS IS THE SIZE DIAL, and it is a literal radius: a
## trap is the set of ground within this distance of its centre.
##
## Every trap is this big. That is the point. See the header comment on
## `sand_at` for why the noise-threshold model this replaced could not do that.
##
## What lands on the ground measures a bit under this -- about 11 m at 13 --
## because the wobble erodes as often as it adds and the fairway edge clips the
## traps that straddle it.
@export var sand_radius := 13.0
## How far a centre may wander from its grid node, 0 (a perfect lattice) to 1
## (nearly half a cell, the most FastNoiseLite offers).
##
## THE CEILING IS SET BY MERGING, not by taste. Push it up and two centres in
## adjacent cells close until their traps fuse into one double-lobed hazard --
## exactly the sprawl this model exists to prevent. The clearance needed is
## `2 * (sand_radius + sand_wobble)`, 33 m as shipped, because two neighbours can
## each wobble toward the other.
##
## MEASURED, NOT DERIVED, and measured CAREFULLY -- both cheaper methods gave
## answers that were wrong in opposite directions. The tidy analytic guess
## (FastNoiseLite offsets a point by up to 0.437 cells, so neighbours close to
## `(1 - 0.874 * jitter) * spacing`) describes the typical case, not the closest
## pair on a whole island, and is far too optimistic. Hunting the distance
## field's local minima on a raster is too pessimistic instead: it finds false
## minima on cell boundaries, which condemned this value at 0.7 when 0.7 is in
## fact fine. The honest number comes from `trap_centres_in_disc`, which refines
## each centre exactly and checks it landed.
##
## Measured that way, against the 33 m clearance: 0.55 clears by 23 m, 0.7 by
## 9 m, and 0.85 touches. Re-measure with `scripts/SCRIPT_measure_sand.gd` if
## `sand_spacing`, `sand_radius` or `sand_wobble` moves.
@export_range(0.0, 1.0) var sand_jitter := 0.7
## Amplitude of the outline wobble, in metres: how far the edge strays from a
## circle. Pure discs read as stamped, so this is what makes the shape a raked
## hazard rather than a coin. Kept under a third of `sand_radius` -- past that
## the wobble starts pinching traps into crescents and detached slivers, which
## is the fractal-fringe failure this model exists to avoid.
@export var sand_wobble := 3.5
## Feature size of that wobble, in metres. Around `sand_radius` gives a handful
## of lobes around a trap's rim; much smaller frays the edge into the fractal
## fringe this model was built to get rid of.
##
## RAISED 16 -> 26 M FOR A SMOOTHER RIM, which is the same argument one notch
## further on. At 16 against a 13 m radius the wobble was turning over faster
## than once per trap diameter, so a bunker's outline crinkled within itself
## rather than lobing: not the fractal fringe, but the last of its texture. 26 is
## twice the radius, which puts two or three lobes on a trap and leaves the edge
## between them clean.
@export var sand_wobble_scale := 26.0
## How sharply a trap's edge cuts in, IN METRES -- the width of the fade from
## grass to sand.
##
## Renamed from `sand_edge` rather than retuned, because the units changed: the
## old one was in noise-mask units, where 0.09 was a sane value and 0.09 m would
## be a razor. A silent unit change on a live name is how you get a preset that
## loads without complaint and renders wrong.
##
## WIDENED 2.5 -> 5 M, and it is the GEOMETRY this buys rather than the albedo.
## `surface_height` builds the trap out of this same weight: a `4s(1-s)` lip that
## peaks at s = 0.5, i.e. squarely in the middle of this band. At 2.5 m the whole
## `sand_rim` (0.7 m) rose and fell inside two and a half metres — a ridge round
## every bunker, and one under the 4 m grid the ground is meshed at past 160 m,
## so it aliased into a ring of facets as you walked away. 5 m spreads the same
## lip over twice the distance and lands it either side of a vertex.
##
## The cost is the fully-sand CORE: `sand_radius` is 13 m, so the disc that
## reaches weight 1 goes from 10.5 m to 8 m while the trap's footprint does not
## move. Re-measure with `scripts/SCRIPT_measure_sand.gd` after changing this — trap
## AREA is what it reports, and area is this number as much as it is the radius.
@export_range(0.1, 12.0) var sand_edge_m := 5.0
## Depth below the surrounding grass, in metres. The ball is 0.18 m across, so
## anything under ~0.4 m stops reading as a hazard you have to chip out of.
##
## COUPLED TO MESH RESOLUTION, and the coupling is the reason this is not simply
## cranked. The dish is carved into the vertex grid, so depth only reads if a
## trap spans enough vertices to curve; at the old 10.7 m spacing a 34 m trap was
## three vertices wide and came out a triangular pit. The grid is 2 m now
## (`chunk_size` 128 over `chunk_cells` 64), and a 13 m radius trap is 26 m
## across -- thirteen vertices -- which carries this comfortably.
##
## LOWERED 3.4 -> 1.4 M, AND THE ~28 DEGREE FACE THIS USED TO CLAIM WAS NEVER
## THERE. That figure came from `atan(2 * depth / radius)`, which is the dish
## term alone -- its own steepest gradient over its own radius -- and the ground
## is not the dish alone. `sand_at` multiplies the radial ramp by a wobbled
## outline, a slope veto and a tee/pin veto, and those fall off together, so the
## real face is far steeper than the dish that nominally makes it. Walked with
## `tests/PROBE_sand_profile.gd` over 480 rays through 30 traps on the hub:
##
##                 depth 3.4      depth 1.4
##   median wall     59 deg         42 deg
##   90th pct        68 deg         55 deg
##   worst           73 deg         62 deg
##   raised lip     0.00 m         0.19 m
##
## A 3.4 m drop at 59 degrees is a pit, not a bunker. The player capsule is 1.8 m
## with the head at 1.6 m, so the rim stood a metre and a half overhead: the
## green you are playing to was invisible and the hazard read as a hole punched
## in the map. At 1.4 m the floor is shoulder high on that capsule and the eye
## sits level with the 1.59 m lip crest -- a sightline that grazes the rim,
## which is what standing in a bunker is supposed to feel like. The ANGLES barely
## move because they are the wobble's, not the depth's; what depth controls is
## how tall that face is, and that is the number the player reads.
##
## Still 7.8 ball diameters, so it is comfortably a hazard by the rule above,
## and every coupling in this comment gets slacker rather than tighter: a
## shallower dish needs fewer vertices to curve, and a gentler wall sits further
## from the slope at which the splat's rock rule would take it over.
##
## Re-measure with `tests/PROBE_sand_profile.gd` after changing this. The
## closed form is not a substitute -- it was wrong here by thirty degrees.
@export var sand_depth := 1.4
## Height of the raised lip around a trap, in metres.
##
## THIS BOUGHT NOTHING UNTIL THE TRAPS GOT SHALLOWER. Lip and dish are summed
## over the same band -- `-depth * smoothstep(s) + rim * (4s(1-s))^2` -- so the
## lip is only visible where it outruns the dish, and at 3.4 m of depth it never
## did: the probe measured a 0.00 m rise above surrounding grass, i.e. the rim
## bought a slower descent and not an edge. At 1.4 m the same 0.7 m rim clears
## grass by 0.19 m, about a third of the way out along the edge band. Raising
## this to compensate would have been the wrong lever: what was drowning it was
## the depth.
@export var sand_rim := 0.7
## Traps are suppressed above this slope (0 = flat, 1 = vertical) so sand doesn't
## run down hillsides.
@export_range(0.0, 1.0) var sand_max_slope := 0.28
## Traps stay this far inland of the coastline, in mask units, so a bunker never
## gets cut in half by the cliff edge.
@export_range(0.0, 1.0) var sand_coast_margin := 0.18
## Clear ground kept around a hole's tee and its pin, in metres.
##
## The tee and the pin ARE the two ends of the fairway capsule — that is the
## whole point of defining a hole as a capsule — so nothing was stopping the trap
## blobs from landing on top of them, and with the layout reshuffled two of the
## nine holes came out teeing off from inside a bunker. Real courses do not put
## sand on the teeing ground or on the pin; this is that rule, applied where the
## geometry already tells us exactly where those two points are.
@export var sand_end_clear := 20.0
## How much sand survives OUTSIDE a golf zone.
##
## Zero by default, which makes the surface language exact: sand means bunker
## means you are on a course. Since golf is hub-only, that also means satellites
## carry no sand at all — deliberate, not an oversight.
##
## Note this is close to all-or-nothing in practice. Sand only becomes the
## dominant surface once it outweighs the grass beside it, so anything under
## about 0.5 tints the rough without ever actually showing sand there. Raise it
## past that, or leave it at 0.
@export_range(0.0, 1.0) var sand_rough_gain := 0.0

@export_group("Crash crater")
## The inciting incident: ONE crater per island, where the player's ship came
## down. Off gives the pre-crater world back exactly.
@export var crater_enabled := true
## Crater radius, in metres — the rim, measured ACROSS the impact line. The gouge
## runs longer than this; see `crater_elongation`.
##
## THE SCALE DIAL, and it does not travel alone. `crater_depth`, `crater_rim` and
## `crater_wobble` are all lengths and all have to move with it or the shape
## changes rather than the size: halving the radius on its own doubles the wall
## angle, which walks straight out of the band `crater_scour_lo`/`_hi` were
## measured against and hands the bowl to the ordinary rock rule. Everything else
## in this group is a FRACTION of the radius and follows for free — which is why
## they are written as fractions.
##
## Bounded below by the mesh, not by taste. Vertex spacing is `chunk_size /
## chunk_cells` = 2 m at LOD0 and coarsens down the ladder, and a dish needs
## upwards of a dozen vertices across before it holds a profile rather than
## coming out as a faceted pit — the lesson `sand_depth` had to learn. At 62 m
## the bowl is 62 vertices across at LOD0 and 16 at the 8 m rungs, so it holds its
## profile all the way down the ladder. At 31 there was still enough (31 and 8) but
## not much spare; below that the lip, the wall and the floor start collapsing into
## two vertices each and none of the three reads.
##
## BACK AT 62 BECAUSE THE SHIP DOUBLED. `crash_site_wreck.wreck_scale` is 2, so the
## hull is 30.0 x 21.4 m in plan where it was 15.0 x 10.7, and a 31 m bowl around a
## 30 m ship is not a crash site — it is a ship wearing a crater. The three lengths
## below moved with it, which is what keeps this a change of SIZE and not of SHAPE:
## every ratio the bowl is made of is unchanged, so the wall angle, the scour bands
## and the flat pad's fit are all exactly as measured. See `crater_depth`.
@export var crater_radius := 62.0
## How much of the bowl is flat floor, as a fraction of the radius. The impact
## melted the substrate and it pooled level; a pure paraboloid all the way to a
## point reads as a funnel, not as a crash site, and leaves nowhere for the ship
## to actually sit.
##
## "NOWHERE FOR THE SHIP TO SIT" IS LITERAL NOW, and this number is set against a
## measurement rather than against the look. `PREFAB_rabbit_v3_crash_site_w2.tscn`
## is the wreck that made this hole, and at `crash_site_wreck.wreck_scale` = 2 its
## hull spans 30.0 x 21.4 m in plan, so it needs 18.4 m of clear radius about
## wherever it is dropped and half its debris sits inside 21.6 m of the same point.
##
## BEING A FRACTION IS WHAT MADE THE SHIP'S DOUBLING FREE HERE. The pad is
## `crater_radius * this`, so at 62 m it went to 24.8 x 36.0 m of half-axis (a
## 50 x 72 m pad) on its own, and the doubled hull seats with 6.4 m of margin all
## round however it is yawed — the same 3.2 m the half-size ship had at the
## half-size crater, scaled. `tests/TEST_island_world.gd` asserts the fit rather
## than trusting this paragraph.
##
## The history is worth keeping because it is what set the number: at 0.34 the pad
## was 10.5 m on the short half-axis against a 15 m hull, so the ship fitted only
## if it landed dead centre and squarely and anything else put a nose or a wing
## over the start of the bowl wall. Debris beyond the pad is MEANT to be climbing
## the wall — thrown rock lands on the slope, that is what makes it ejecta rather
## than a spill.
##
## WHAT IT COSTS IS THE WALL, which narrows from 66% of the radius to 60%, so the
## bowl's mean gradient rises about a tenth (0.330 -> 0.363) and the wall runs a
## little steeper for the same depth. That stays well inside the regime
## `crater_scour_lo`/`_hi` were measured in and does not change what classifies as
## what; it is still a re-measure if this moves much further. See those two.
##
## AND IT IS HELD ABOVE `crater_molten` (0.30) BY CONFIGURATION, not by luck —
## `tests/TEST_island_world.gd` asserts the order. The pool has to end on flat
## ground or the melt is running uphill; raising the floor only ever makes that
## safer, which is the direction this moved.
@export_range(0.0, 0.9) var crater_floor_frac := 0.40
## Pin the floor to a single datum instead of letting the island's relief through.
##
## THE LIFT WAS ALWAYS FLAT AND THE FLOOR WAS NOT, which is the distinction this
## switch exists to make. `bowl` is pinned at exactly 1 inside `crater_floor_frac`,
## so the height OFFSET across the floor is a constant `-crater_depth` — but it is
## an offset, and the ground under the crash site is a wooded hillside that goes on
## rising underneath it. Measured on the shipped seed the "flat" floor fell 0.86 m
## across itself. Off restores that, for an A/B; see `crater_at` for the correction.
@export var crater_flat_floor := true
## Bowl depth at the floor, in metres, below the surrounding ground.
##
## Coupled to `crater_radius` exactly the way `sand_depth` is: what the eye reads
## is the wall ANGLE, and the bowl is a smoothstep, so its steepest point is 1.5x
## its mean gradient — `atan(1.5 * depth / (radius * (1 - floor_frac)))`, which at
## 13.5 m in a 62 m bowl with 40% of it floor is ~28.6 degrees.
##
## THAT ANGLE IS WHY THIS DOUBLED WITH THE RADIUS AND WAS NOT RE-TUNED. The
## expression is a RATIO of two lengths, so scaling both leaves it exactly where it
## was — the bowl at 62 x 13.5 has the same wall as the bowl at 31 x 6.75, and
## every measurement taken against that wall (`crater_scour_lo`/`_hi` above all)
## still holds without re-measuring. Move one of the two on its own and none of
## that survives.
##
## NOT the `2x` a bunker's cubic dish gives. That factor is where the first pass
## at `crater_scour_lo` came from and it was wrong by three, which put the scour
## band above every slope the bowl actually has and classified the whole thing as
## dirt. If this ratio moves, re-measure rather than re-deriving.
##
## Held under the ~40 degrees at which the splat's ordinary rock rule would take
## the walls over on its own, which would make the crash site look like every
## other crag on the island.
@export var crater_depth := 13.5
## Height of the raised lip above the surrounding ground, in metres. This is the
## ejecta ring — material thrown out of the hole and dropped around it. A length,
## so it scales with `crater_radius`.
@export var crater_rim := 4.2
## How far inside the rim the lip starts to rise, as a fraction of the radius.
## Small: the inner face of a lip is the steep one, because the ejecta was piled
## against the hole it came out of.
@export_range(0.02, 0.6) var crater_lip_inner := 0.12
## How far outside the rim the lip falls away, as a fraction of the radius. Wider
## than `crater_lip_inner` by design — the outer slope is a drift, not a wall,
## and the asymmetry between the two is most of what makes a rim read as thrown
## rather than as a moulded ring.
@export_range(0.05, 1.5) var crater_lip_outer := 0.46
## How far past the rim the CHARRED GROUND reaches, as a fraction of the radius.
##
## Wider than `crater_lip_outer` on purpose: the blast scorched further than it
## piled. Ending the paint at the lip draws a tidy ring of burnt earth with a
## clean green edge, which reads as a decal; carrying it out past the geometry
## into a fading ash apron is what makes it read as a burn. This is also the reach
## the burnt-vegetation pass will want to key off later.
##
## MUCH SHORTER THAN IT STARTED, and the correction came from a picture rather
## than from an argument. At 0.85 it multiplied a long axis that was then 95 m
## into a 350 m disc of charred ground — and rendered, the crash site stopped
## being a crater in a landscape and became a landscape. Every frame from the rim
## was burnt earth to the treeline, which reads as terrain that is simply this
## colour here, not as damage. The bowl is the event; this is the collar around
## it, and a collar is the smaller thing.
##
## Being a FRACTION is what let the crater halve without this being touched.
##
## Read it against `crater_lip_outer` (0.46) rather than on its own: the burn has
## to finish OUTSIDE the geometry it is explaining or the lip's outer flank comes
## back green, and 0.45 against 0.46 is very nearly the tightest it can be while
## still doing that. The `crater_burn` remap is what buys the margin — the char is
## still saturated a good way past the rim and only fades over the last stretch.
@export_range(0.0, 2.5) var crater_ash_reach := 0.45
## Metres of wobble on the crater's radius, and the feature size of that wobble.
## Same construction as `sand_wobble`: it perturbs the outline without moving the
## area much, so a crater is never a circle you could measure with a compass.
##
## BOTH ARE LENGTHS and both scale with `crater_radius`. The second is the one
## that is easy to leave behind: hold the feature size while the crater shrinks
## and the outline stops being ragged and starts being lumpy, because the same
## number of wobble periods no longer fits round a smaller rim. At 5.5 m of
## wobble on a 31.0 m feature the edge keeps roughly the lobe count it had at
## half the size.
@export var crater_wobble := 5.5
@export var crater_wobble_scale := 31.0
## How much longer the crater is along the ship's approach than across it. A
## vertical impact digs a circle; anything arriving on a trajectory ploughs an
## ellipse, and the elongation is what lets a player standing on the rim read
## which way the ship was travelling.
@export_range(1.0, 3.0) var crater_elongation := 1.45
## How much shallower the bowl is at the ENTRY end, 0..1. The ship came in low,
## touched down and dug in progressively, so the near end is a ramp and the far
## end is a wall. This is also the way out on foot, which is the one gameplay
## consequence of the whole feature: at 0 the crash site is a pit the player
## cannot climb out of.
##
## IT IS A PROPERTY OF THE WALL AND NOT OF THE FLOOR, and that gate is in
## `crater_at` rather than here — see the `ramp` line, which is what actually
## makes `crater_floor_frac` mean a FLAT floor. Ungated this term multiplies the
## depth everywhere the bowl reaches, the flat pad included, so the "floor" came
## out tilted almost a metre across itself and the one part of the feature that
## was supposed to be level was not.
@export_range(0.0, 0.95) var crater_entry_ramp := 0.62
## How much higher the lip is piled at the FAR end than at the entry, 0..1.
## Everything the gouge displaced ended up in front of it.
@export_range(0.0, 1.0) var crater_far_throw := 0.55
## Degrees the approach may yaw off straight-inland, either way. Zero would aim
## every crater at the middle of its island, which from the rim reads as the
## ship having been fired at the target rather than having come down on it.
@export_range(0.0, 90.0) var crater_heading_spread := 34.0
## The value the crater weight passes through at the rim CREST — the join between
## the curve's two pieces, inside the rim and out.
##
## THIS IS A RADIAL COORDINATE, NOT A DOSE OF CHAR, and keeping those two apart is
## the whole reason the curve is shaped the way it is. Read as "the crest is 45%
## burnt" it is obviously too low: what that draws is an ash ring with grass
## showing through it. Raising it to fix that was tried and cost more than it
## bought — the interior span collapsed from 0.55 to 0.28, and `crater_fuse_weight`
## and `crater_scour_floor` are LEVELS ON THIS CURVE, so the floor, the wall and
## the lip ended up separated by six hundredths and the classification went to
## speckle wherever `crater_wobble` moved the outline.
##
## So the curve keeps its wide interior for the levels to sit in, and how burnt
## the ground actually LOOKS is a separate remap — `crater_burn`, which is at 1.0
## well before the crest. One channel, read twice, for two different questions.
@export_range(0.05, 1.0) var crater_rim_paint := 0.45
## The crater weight at and above which the ground is FULLY charred.
##
## Set below `crater_rim_paint`, so the lip crest and a good way out into the
## ejecta are burnt outright and the fade is spent on the outer apron — which is
## the part that is genuinely half there. See `crater_burn`.
@export_range(0.02, 1.0) var crater_char_full := 0.34
## Mask value the crater centre is placed at — 0 is the coastline, 1 the island's
## middle.
##
## Not a distance in metres, because the coastline wobbles: a fixed inset from a
## jagged shore lands in the water on one bearing and 200 m inland on the next.
## Solving for a mask LEVEL puts every crater the same distance in from the shore
## as the shore actually runs.
##
## WAS 0.17, WHICH PUT THE CRASH SITE ON THE BEACH. At that level the excavation
## cleared the coastline by 0.053 of mask on the shipped hub, against a
## `crater_coast_margin` of 0.05 — it was passing the cliff rule by three
## thousandths — and it sat on bare shore ground, because `forest_at` multiplies
## its noise by `smoothstep(0, forest_coast_margin, mask)` and the shore is bald
## by construction. A ship that came down in a wood is a better picture and a
## better place to stand, so the site moved inland.
##
## IT IS NOT "AS FAR INLAND AS POSSIBLE", AND THAT IS THE MEASUREMENT THAT SET IT.
## The wood is a BAND, not a middle: the canopy is cut off at the shore by
## `forest_coast_margin` and again on the interior peaks by `forest_max_slope`,
## so walking further in past a point walks straight back out of the forest.
## Censused over the hub at 40 m (tests/PROBE_crater_forest.gd):
##
##   mask band    0.0-0.1  0.1-0.3  0.3-0.5  0.5-0.65  0.65-1.0
##   mean forest    0.10     0.29     0.26      0.13      0.16
##   wooded          9%      30%      27%       12%       16%
##
## WHAT PINS IT AT 0.30 IS A WINDOW WITH A RULE CLOSING IT FROM EACH SIDE, and it
## takes BOTH shipped presets to see that — this was set to 0.40 first, off the
## W2 hub alone, and the golf preset would have paid for it. Bearings clearing
## both hard rules, out of 24 (tests/PROBE_crater_pick.gd):
##
##                     0.17  0.22  0.26  0.30  0.34  0.40
##   hub_solid (W2)      11    15    22    23    21    14
##   default (golf)      11    15    15    10     8     2
##
## Below 0.30 the losses are the COASTLINE — the excavation hangs over the
## contour on bearing after bearing. Above it they are the COURSE, and the golf
## preset fills its interior with fairways, so by 0.40 it is down to two
## candidates and one notch from the fallback that would put the crash site in a
## fairway. 0.30 is where the coast has stopped rejecting anything on the W2 hub
## and the course has taken only one: the widest the window gets.
##
## Across eight seeds it moves the site from 276 m inland to 365 m, and takes the
## forest under the footprint from 0.25 to 0.75 and the burning collar from 0.23
## to 0.67. Both presets end up on the best site their island offers — 0.77 on
## the W2 hub at 413 m inland, 0.82 on the golf hub at 328 m.
##
## It also stops the excavation living on the cliff rule's margin. Worst mask
## anywhere on the bowl ring, over those eight seeds, against a
## `crater_coast_margin` of 0.05:
##
##   before   mean 0.066, tightest 0.053   — passing by three thousandths
##   after    mean 0.159, tightest 0.089
##
## That is a consequence and not a second objective, and it is worth being exact
## about WHY, because the obvious reading is wrong: raising the request only moves
## a GIVEN bearing away from the contour, and the bearing that wins changes, so
## the realised clearance is free to go either way and on the hub it lands at
## 0.095 rather than the 0.195 the 0.40 site had. What actually buys the margin is
## that the coastline stops rejecting candidates at all, so nothing is left
## scraping past it.
##
## A REQUEST, NOT THE ANSWER. `_place_crater` raises it wherever the footprint
## would not fit inside it — see the derivation there. Raising it can only ever
## help the cliff rule, since it moves the excavation away from the contour; what
## it spends is candidates, as the course fills the middle of the island.
@export_range(0.02, 0.9) var crater_shore_mask := 0.30
## The crater must clear the coastline by this much mask, or the bowl punches
## through the contour and the cliff sweep hangs off a hole. Checked at the rim,
## not at the centre.
@export_range(0.0, 0.9) var crater_coast_margin := 0.05
## Zone weight a candidate site may not exceed. A crash site is wild ground: it
## reads as an accident, and a crater cut through the middle of a fairway reads
## as a course feature. Also practical — `zone_at` flattens a zone to a shelf and
## the crater would be fighting it for the same vertices.
@export_range(0.0, 1.0) var crater_zone_max := 0.02
## How many bearings the placement tries before giving up and taking the best it
## saw. See `_place_crater` — the search is over a ring, so this is an angular
## resolution rather than a budget that can run out.
@export_range(4, 64) var crater_place_attempts := 24
## Only islands at least this big carry a crater. A satellite the size of the
## crater would be a doughnut.
@export var crater_min_radius := 300.0
## Restrict crash sites to hub islands.
##
## On by default and for the same reason golf is: one crater per hub is an event,
## and a crater on every rock in the sky is scenery. Turn it off and every island
## over `crater_min_radius` gets one.
@export var crater_hub_only := true

@export_group("Crater surface")
## Slope band the crater's ground scours to fused rock over — onset in the first,
## fully scoured by the second. 0 is flat, 1 vertical.
##
## FAR BELOW the ordinary `rock_band()` (0.29 .. 0.42 as shipped), and the gap is
## the point rather than an oversight. Ordinary rock means "too steep to weather,
## too steep to stand on"; crater rock means "the ground here was blown off",
## which happens at angles erosion never reaches.
##
## MEASURED, not chosen, and the first pass at it was wrong by a factor of three
## because the arithmetic was. A bowl `crater_depth` deep across
## `(1 - crater_floor_frac)` of its radius has a MEAN gradient of 6.75 / 20.5 =
## 0.33, and a smoothstep's steepest point is 1.5x its mean, not the 2x a
## bunker's cubic dish gives — so the wall tops out near 26 degrees, which is
## `1 - cos(26)` = 0.10 in these units and not the 0.3 the first band assumed. At
## 0.10 .. 0.30 the entire bowl classified as dirt, and the only thing the rule
## fired on was the lip, which is the one part of a crater that must NOT scour —
## hence `crater_scour_floor`.
##
## RE-MEASURED WHEN THE CRATER HALVED, and it had to be even though the crater
## kept its proportions exactly. `curvature_radius` is a FIXED 4 m, so a wall
## that spans 20.5 m is smoothed by it a good deal harder than one spanning 41,
## and the same geometry reads shallower. Sampled 24x24 polar over the bowl:
##
##                 at radius 62      at radius 31
##   floor         0.003 / 0.004     0.003 / 0.008    (mean / p90)
##   lower wall    0.055 / 0.118     0.035 / 0.086
##   upper wall    0.093 / 0.209     0.082 / 0.154
##
## So the band came down with it: 0.028 .. 0.10, which is above the floor's
## maximum of 0.019, through both walls, and still nowhere near flat ground. Scale
## the crater again and re-measure again — this is the one number in the group
## that does not follow `crater_radius` by arithmetic, because what it is really
## measured against is the ratio between the wall and `curvature_radius`.
@export_range(0.0, 1.0) var crater_scour_lo := 0.028
@export_range(0.0, 1.0) var crater_scour_hi := 0.10
## Crater weight the slope rule needs before it may scour anything, and the width
## it comes up over.
##
## THE LIP IS AS STEEP AS THE WALL IS, and without this gate that is fatal to the
## whole surface. `crater_scour_lo` is set low on purpose — blasted ground scours
## at gentler angles than weathered ground ever does — and the lip's inner face,
## rising `crater_rim` over `crater_lip_inner` of the radius, is one of the
## steepest things in the feature. Ungated, the slope rule fused the entire lip
## to slag and the crater rendered as a red bowl with a red ring round it and no
## charred band anywhere: every part of the picture that was supposed to be ash
## was the one surface the ash is defined against.
##
## The gate is a level on the paint curve, so it is stated in the same units as
## `crater_rim_paint` and has to sit just above it — above the crest means the
## lip cannot scour, and the bowl below it still can.
@export_range(0.0, 1.0) var crater_scour_floor := 0.48
@export_range(0.01, 1.0) var crater_scour_floor_width := 0.08
## Crater weight above which the ground is fused whatever its slope. The floor is
## the flattest ground in the whole feature and the slope rule alone would leave
## it as dirt — but it is the part that actually took the impact, so it is the
## part that melted. This is what puts the glowing crust in the bottom of the
## bowl rather than only on its walls.
@export_range(0.0, 1.0) var crater_fuse_weight := 0.62
## How far out from the impact point the substrate is still LIQUID, as a fraction
## of the crater's radius. 0 switches the molten pool off and leaves the floor as
## a cooled crust with live cracks in it.
##
## HELD INSIDE `crater_floor_frac`, deliberately, so the pool's edge sits on the
## flat floor rather than partway up the bowl wall. A melt that ran up the wall
## would be a melt that flowed uphill, and the eye catches that immediately even
## when it cannot say why.
##
## THIS IS THE ONE RADIAL QUANTITY `crater_at().y` CANNOT PROVIDE, which is why
## it is a third channel rather than another level on that curve. The paint
## weight is pinned flat at exactly 1.0 across the whole floor -- that is what
## `crater_floor_frac` means -- so every rule written on it is blind inside the
## rim, and "hotter toward the middle" is precisely a rule about the inside of
## the rim. See `crater_at`.
@export_range(0.0, 0.9) var crater_molten := 0.30

@export_group("Escape pod divot")
## The second impact: where the escape pod came down, one per island that already
## carries a crash site. Off gives the pre-pod world back exactly.
##
## GATED ON THE CRATER, not independent of it. A pod with no ship it came out of
## is a dent in a field, and `_place_divot` returns null when `crater_for` does —
## which also means every switch that governs the crash site (`crater_enabled`,
## `crater_hub_only`, `crater_min_radius`) governs this without being restated.
@export var divot_enabled := true
## Trough radius, in metres, measured ACROSS the skid. The dent runs longer than
## this along it; see `divot_elongation`.
##
## THE SCALE DIAL, and like `crater_radius` it does not travel alone: `divot_depth`,
## `divot_bank` and `divot_wobble` are lengths and have to move with it or the
## shape changes rather than the size.
##
## SIZED AGAINST THE POD, WHICH IS 3.1 x 3.6 m ON THE GROUND AND 4.15 m TALL
## (`models/MODEL_escape_pod.glb`, measured). At 7 m across and 2.0 elongation the
## trough is 14 x 7 m of floor before the walls start, so the pod occupies about a
## quarter of the dent's length — enough that the skid behind it reads as a skid
## and not as a socket cut to fit. A crater is 62 m across for a 15 m ship; this
## is deliberately the tighter ratio, because a dent is the record of something
## STOPPING and a crater is the record of something exploding.
@export var divot_radius := 7.0
## How much longer the dent is along the pod's travel than across it. Higher than
## `crater_elongation` (1.45) on purpose: the ship arrived and detonated, the pod
## arrived and SLID, and the length of the mark is the whole of what says so.
@export_range(1.0, 4.0) var divot_elongation := 2.0
## Fraction of the radius that is flat floor. The pod stands on it, so it is the
## one part of the shape that has to be genuinely level, and it is pinned to a
## datum for that — see `Divot.floor_base_y`.
@export_range(0.0, 0.9) var divot_floor_frac := 0.34
## How deep the trough is cut below the surrounding ground, in metres.
##
## SHALLOW, AND THAT IS THE POINT: "more like a dent in the ground than an
## explosion". At 0.9 m against the pod's 4.15 m height the dent takes about a
## fifth of the pod out of the skyline, which reads as settled rather than buried.
## Anything past about 2 m stops being a dent and starts being a small crater —
## and the moment the ground closes over the pod's waist the bank stops being
## readable as the thing holding it up.
@export var divot_depth := 0.9
## How far the BANK stands above the surrounding ground at the far end, in metres.
##
## THIS IS THE ASYMMETRY, and it is the number the pod's pose is built on —
## which means the thing to tune it against is THE LEAN ANGLE, not the bank's own
## height. The pod rests on the bank's CREST, so how upright it ends up is
## `atan(run / rise)` from its contact edge to that crest, and the run is fixed by
## `divot_bank_inner`: taller bank, more upright pod. Measured on the shipped hub,
## through `tests/TEST_escape_pod.gd`, which prints the solved angle:
##
##     bank   crest above grade   pod leans
##      1.4         1.33 m           55.0 deg   — half fallen over
##      2.4         2.29 m           42.5 deg
##      3.0         2.86 m           36.5 deg   — shipped
##      3.6         3.43 m           33.0 deg   — diminishing, and now a pit
##
## 3.0 IS WHERE "SEMI-UPRIGHT" ACTUALLY LANDS. At 36.5 degrees the pod's top sits
## 3.34 m above its foot, level with the 3.39 m crest to within five centimetres —
## nestled into the bank rather than towering over it — and 1.8 m of it stands
## clear of the ground BEYOND the bank, which is the measurement that decides
## whether anyone walking up to it can see it. Going taller buys three degrees a
## metre and starts closing the ground over the pod; going shorter tips it past 45
## and it reads as fallen rather than as leaning.
##
## THE FIRST PASS TUNED THIS AGAINST THE WRONG DATUM and it is worth recording
## why, because the wrong one is the obvious one. Measuring the crest above the
## TROUGH FLOOR gave 5.02 m against a 4.15 m pod — "121% of the pod, it is in a
## pit" — and the bank was cut to 1.4 on that reading. But the pod does not stand
## on the floor: `escape_pod.stand_frac` puts it at the foot of the bank, up the
## wall and very nearly at grade, so the floor's depth is not under it at all. The
## number that governs is the crest above WHERE THE POD IS.
##
## THE ENTRY END GETS NONE OF THIS. `divot_at` gates the whole lip term on the
## far half, so the near end has no rim at all and the skid runs out into open
## ground. A dent with a rim all the way round is a crater, and a small crater is
## exactly what this feature is not.
@export var divot_bank := 3.0
## How sharply the bank is confined to the far end. The lip is multiplied by
## `max(along, 0)` raised to this, so 1 spreads it over the whole far half and
## higher numbers pull it into a crescent at the stop point.
##
## 2.0 puts the crest within about 40 degrees of dead ahead, which is what makes
## the bank read as the thing the pod hit rather than as half a rim.
@export_range(0.5, 6.0) var divot_bank_focus := 2.0
## Where the bank's inner face rises, as a fraction of the radius inside the rim.
## Tighter than `crater_lip_inner` (0.12) because this face is a SCARP the pod is
## resting on and a drawn-out ramp would let it slide back down.
@export_range(0.02, 0.6) var divot_bank_inner := 0.09
## And how far it drifts out on the far side, as a fraction of the radius. Wide,
## because the far side of the bank is spoil pushed up a hillside and nothing
## about it was thrown.
@export_range(0.05, 1.5) var divot_bank_outer := 0.55
## How open the entry end is: how much of the trough's depth is given back along
## the skid, so the ground rises out the way the pod came in.
##
## MEASURED FROM THE EDGE OF THE FLOOR, exactly as `crater_entry_ramp` is, and for
## the same reason — read off the raw along-coordinate it would keep varying
## across the pad the floor pin just levelled, and the pod would sit nose-up in
## ground that was supposed to be flat. See `divot_at`.
@export_range(0.0, 1.0) var divot_entry_open := 0.85
## Metres of wobble on the dent's outline, and the feature size of that wobble.
## Both are lengths and both scale with `divot_radius`. Small against the crater's
## 5.5 m: a dent this size with the crater's wobble on it would be all lobe and no
## dent.
@export var divot_wobble := 0.9
@export var divot_wobble_scale := 7.0
## The value the divot's paint weight passes through at the bank CREST — the join
## between the two halves of the paint curve, in the same units and playing the
## same role `crater_rim_paint` does.
@export_range(0.05, 1.0) var divot_rim_paint := 0.40
## How far the scuffed ground drifts out past the rim, as a fraction of the
## radius. Short: earth pushed aside by a landing does not travel, and the thing
## this is NOT is an ash apron.
@export_range(0.0, 2.5) var divot_scuff_reach := 0.30
## The divot weight at and above which the ground is fully torn — the remap
## `divot_scuff` applies, and the counterpart of `crater_char_full`.
@export_range(0.02, 1.0) var divot_scuff_full := 0.30
## Slope at and above which torn ground inside the dent shows STONE rather than
## earth: the scarped face of the bank, and the gouge where the pod's hull went
## through the topsoil.
##
## Well below the ordinary rock onset, for the reason `crater_scour_lo` is: this
## is not "too steep to hold soil", it is "the ground here was cut". Read against
## the bank's actual face, which climbs `divot_bank` (3.0 m) over
## `divot_bank_inner * radius * elongation` = 1.26 m of run — steeper than 60
## degrees in the field, and scarp by any measure. What the MESH does with it is
## another question: the ground is a height field on a 2 m grid, so what actually
## gets built is nearer 35 degrees, and the splat has to classify the face the
## field describes rather than the one the vertices manage.
@export_range(0.0, 1.0) var divot_scarp_lo := 0.06
@export_range(0.0, 1.0) var divot_scarp_hi := 0.20
## How far, in metres, the divot's centre must be from the crash site's — and,
## because the search now takes the NEAREST bearing that clears this rather than
## the furthest, very nearly how far away the pod actually ends up.
##
## "A WAYS AWAY FROM THE SHIP, AND STILL PLAINLY THE SAME EVENT" is the
## requirement, and it is a stated distance rather than a derived one because what
## it is protecting is a READING and not a geometry. It has been wrong in both
## directions. Too close and the pod is more debris from the crash: the footprints
## stop overlapping at `crater_outer_radius` + `divot_outer_radius`, 162 m on the
## shipped numbers, and two marks 162 m apart on a 2.5 km island are one debris
## field. Too far and the tie is cut the other way — this was 420 m ranked
## FURTHEST-WINS, which put the dent 1,643 m away on the shipped hub, the far side
## of the island, where nothing about the pod says which ship it came out of.
##
## WHY 360. It is the tightest the near limit goes without breaking the standoff
## `tests/TEST_escape_pod.gd` asserts — more than twice the two footprints put
## together, 325 m — which is the line between "outside the burnt collar" and
## "unrelated to it". At 360 the crater's collar ends 139 m from its centre and
## the pod's scuff 23 m from its own, so about 200 m of untouched ground lies
## between the two: a walk of a couple of minutes, each visible from the other,
## neither standing in the other's debris.
##
## `_place_divot` checks this against the crater's CENTRE, not its rim, so the
## number means what it says and does not move when the crater is resized.
@export var divot_crater_clearance := 360.0
## How much higher the base ground must still be one `divot_outer_radius` beyond
## the dent, in metres. Candidates on ground that is not still climbing there are
## rejected outright.
##
## THE POD HAS TO HAVE SOMETHING TO LEAN ON, and `_divot_heading` alone does not
## guarantee it. That reads the gradient off a cross `divot_uphill_span` (14 m)
## wide, which is INSIDE the dent — so it faithfully answers "which way is up from
## the middle of the trough" and says nothing at all about what is behind the bank
## the trough's far end is about to cut. A ridge crest passes that test perfectly:
## the ground rises for the fourteen metres it is asked about and then falls away.
##
## AND A BANK WITH NOTHING BEHIND IT DOES NOT HOLD THE POD. This is not a matter
## of taste, it is what the settle does — measured on the hub, at the candidate
## 504 m from the crash site, which is a textbook crest: the ground climbs 0.74 m
## over the 14 m `_divot_heading` looks at, and 23 m out it is 0.26 m BELOW where
## it started, having dropped 3.6 m off the back of the bank.
##
##     ground beyond   what the settle does
##       -0.26 m       lands at 24 deg, creeps forward, goes OVER the crest and
##                     comes to rest at 83 deg — on its side, down the far slope
##       +2.44 m       lands at 24 deg and stops there; 93 frames, done
##
## The pod is 4.15 m tall and the bank stands `divot_bank` (3.0 m) above grade, so
## a pod leaning into the crest has its top ABOVE it either way. What decides the
## outcome is whether the ground behind the crest catches the top or lets it keep
## going, and one sample past the dent's own reach is what tells those apart.
##
## 1.0 m OVER 23 m is a gradient of 4% — barely a hillside, and deliberately so:
## this is a rule against ridges and knolls, not a demand for a mountainside. On
## the shipped hub it rejects 13 of the 32 bearings the search tries and leaves 19
## standing, so it changes WHICH candidate wins without ever being the reason
## there is none.
@export var divot_hill_rise := 1.0
## Mask level the divot's centre is placed at, on the same 0-at-the-coastline
## scale `crater_shore_mask` uses, and raised the same way when the trough would
## not fit inside it. Deeper inland than the crater's 0.30: the pod was thrown
## clear and carried on, so it came down further in than the ship did.
@export_range(0.02, 0.9) var divot_shore_mask := 0.45
## The divot must clear the coastline by this much mask. Same rule and the same
## reason as `crater_coast_margin` — the cliff sweep hangs off the coastline
## contour, and a trough cut through it is a hole in the cliff.
@export_range(0.0, 0.9) var divot_coast_margin := 0.04
## The most zone influence a divot's footprint may sit in. A pod parked on a
## fairway reads as a prop; the crater's rule and the same argument.
@export_range(0.0, 1.0) var divot_zone_max := 0.02
## How many bearings the placement search tries.
@export_range(4, 64) var divot_place_attempts := 32
## How far apart, in metres, the two height samples the uphill heading is taken
## from sit. One trough length: sampled closer the gradient is the hill noise's
## finest octave and the pod ends up aimed at a hummock, sampled much wider it is
## the island's dome and every pod on every seed points at the peak.
@export var divot_uphill_span := 14.0

@export_group("Ruin entrance")
## Level a clearing for the RUIN ENTRANCE near the player start — or one for each of
## a ring of them round the island, `ruin_ring_count` — and report where they are so
## `SCRIPT_ruin_site.gd` can stand a prefab in each.
##
## OFF IN THE SCRIPT AND ON IN THE ONE PRESET THAT SHIPS IT, and that split is the
## point. The crater and the divot are on by default because every hub is meant to
## have had a crash; the ruin is an authored landmark for ONE island —
## `data/ISLANDFIELD_hub_solid.tres`, which is `SCENE_island_0`'s — and a clearing
## levelled on every other preset would be a disc of flat ground with nothing
## standing in it. Off gives the pre-ruin world back exactly.
##
## GATED ON THE DIVOT, not independent of it: the site is measured from the player
## start, the player starts at the pod, and `_place_ruin` returns null when
## `divot_for` does. No pod, no start, no ruin. A ring is measured from the island's
## centre instead and stands with or without one.
@export var ruin_enabled := false
## Radius of the dead-flat core, in metres. A COPY OF THE MODEL'S OWN NUMBER, not a
## choice.
##
## `CLAUDE__groundIntersectionPlaneAndTerrainSlopeMask` in
## `models/MODEL_ruin_entrance_type1.glb` is a 48-segment disc at node scale
## 21.57449, which puts its rim at 25.889 m from the ruin's axis. The field cannot
## read it — this is a pure function of world XZ, evaluated in bake tools and on
## mesher workers with no scene loaded — so it carries the number, and
## `tests/TEST_ruin_site.gd` loads the prefab, reads the disc through
## `RuinEntrance.mask_radius()` and FAILS if the two disagree. Re-export the model
## with a different disc and the test names this line.
##
## WHAT THE DISC COVERS, measured off the prefab: the tower, whose widest part
## (`ruinLower`) is 4.17 m in radius, and the square tile apron, whose edges are
## 21.07 m from the axis — so the disc reaches 4.8 m past the apron's edges and
## falls 3.9 m short of its corners, which are 29.80 m out. The corners are the slope band's
## problem, and `ruin_slope_band` is where that is settled.
@export var ruin_flat_radius := 25.889
## Height of the ground intersection plane above the MODEL's origin, in metres. The
## other copy of the disc: its Y, 0.76155 in the .glb.
##
## THE TERRAIN DOES NOT NEED IT, and it is carried anyway because it is half of
## what the modeller's note says. `PREFAB_ruin_entrance_type1.tscn` lowers the
## model by this much so the prefab's origin IS the plane, which is what lets
## `SCRIPT_ruin_site.gd` stand the prefab at `RuinSite.floor_y` with nothing added;
## a disc re-drawn at another height would leave the prefab's offset and this
## number both stale, and the test checks all three against the mesh so that
## cannot happen quietly. It is also the one honest answer to "where does the
## MODEL's own origin land" — `RuinSite.floor_y - ruin_plane_height` — which the
## probe prints.
@export var ruin_plane_height := 0.76155
## Width of the ring outside the flat core over which the ground eases back to its
## own shape, in metres. The disc's name calls it a "terrain slope mask", and this
## is the slope: flat inside the disc, then the hillside returning, with no cliff at
## the rim.
##
## THE PROFILE IS A SMOOTHSTEP, for the property that makes it read as ground
## rather than as an earthwork: its slope is ZERO at both ends. So there is no
## crease where the levelled disc meets the band and none where the band meets the
## untouched hill — the same two-sided ease `zone_at` uses for every bank on the
## island. Its steepest point is 1.5x the mean, so the worst gradient in the band
## is `1.5 * relief / this`.
##
## 20 M, AND FOUR THINGS SET IT:
##
##   * THE TILE CORNERS — THE CORNER DECISION. The apron is a 42.13 m square and
##     the disc is round, so each corner stands 3.9 m out into this band. The disc
##     is NOT widened to swallow them: it is the modeller's statement of what has to
##     be flat, and a field that levelled a bigger patch than the note asked for
##     would be overriding the note. Instead the corners ride the smoothstep's slow
##     start. 3.9 m into a 20 m band it has only climbed to 0.099, so a corner
##     stands within a tenth of the local relief of the plane — and with the relief
##     capped by `ruin_earthwork_max` at 3 m, that is 0.30 m either way: under the
##     0.385 m the tiles stand proud of the plane, so no corner is ever buried, and
##     nowhere near the 1.91 m they reach below it, so none ever floats. The corner
##     is then a plinth edge showing between 0.09 and 0.69 m of stone, which is
##     what an old apron on real ground looks like. BY CONSTRUCTION, not by luck of
##     the site — though the cap is sampled on rings either side of the corners
##     rather than at them, which is why `tests/TEST_ruin_site.gd` measures the real
##     corners against the real tile mesh anyway. At 16 m the same corner is 0.15
##     of the relief (0.45 m, past the tiles' top), at 12 m 0.25 (0.74 m): either
##     buries the uphill corners of a site the cap allows, and 20 is the first
##     round number that does not.
##   * THE BANK. At the cap the steepest ground in the band is 1.5 * 3 / 20 = 0.225,
##     under 13 degrees: walkable in every direction, a long way under the 0.294 at
##     which `rock_band` starts painting scree, and gentle enough to read as a
##     clearing rather than as a platform.
##   * THE MESH. 20 m is ten cells at the 2 m LOD0 grid and still two and a half at
##     the 8 m rungs, so the band is a curve on every rung it is seen from rather
##     than a single stepped facet round a disc.
##   * WHAT IT COSTS, which is sites. The band is ground the earthwork cap is
##     checked over, so every metre of it is a metre more hillside that has to be
##     gentle. Candidates in the whole walk band that clear every hard rule, by
##     `tests/PROBE_ruin_site.gd`'s sweep on the shipped hub:
##
##         band    12    16    20    24
##         sites   77    52    20     9
##
##     20 still leaves the search a choice; 24 all but removes it, and on a
##     different seed would be the width at which there is no site at all.
##
## ON THE SHIPPED SITE the relief is under the cap, so the corners and the bank see
## less than the worst case: corners at -0.16 .. +0.12 m, steepest bank 0.225
## (the natural slope there adds to the band's own). The probe prints both.
@export var ruin_slope_band := 20.0
## The walk from the player start to the site, in metres, measured from the
## divot's centre: nearer than the first ring is not considered and further than
## the last is not near.
##
## THE FLOOR IS MOSTLY THE POD'S, NOT THIS NUMBER'S. The footprint has to clear the
## dent's own by `ruin_feature_gap`, which alone puts the nearest possible centre
## 23 + 12 + 46 = 81 m out; 60 is only the floor on a world with a smaller clearing.
## The ceiling is 44 seconds' walk at the 4.5 m/s the encounter spacing is paced
## against; past it a landmark is somewhere else on the island rather than part of
## the place the game starts.
@export var ruin_start_min := 60.0
@export var ruin_start_max := 200.0
## How far inland the whole footprint must stay, in mask units. The zones' own
## number, `zone_coast_margin`, and for the zones' reason: it is past `shore_width`
## (0.22), so the levelled plane never lands on the shore ramp, where the ground is
## scaled toward the coastline and a flat disc would stand proud of a slope falling
## into the sea.
@export_range(0.0, 0.9) var ruin_coast_margin := 0.25
## The most zone influence the footprint may sit in — and the walk to it. The
## divot's number and the divot's argument: a ruin on a fairway's bank reads as a
## course feature, and two flattenings competing for the same vertices is a bank
## nobody designed. A walk that stays off every zone's grooming also never meets a
## golf wall, which stands INSIDE the grooming — see `_ruin_path_clear`.
@export_range(0.0, 1.0) var ruin_zone_max := 0.02
## Clear ground kept between the ruin's footprint and the crash site's, and between
## it and the pod's dent, in metres — footprint edge to footprint edge. On a ring, also
## between any two entrances' footprints, which is what lets `ruin_near` hand every
## point to one clearing.
##
## THE POD IS WHAT SETS IT. `SCRIPT_escape_pod.gd` settles the pod on a 20 m patch
## sampled out of this field around a release point ten metres from the dent's
## centre, so the ground it lands on reaches 24.5 m out — 1.4 m past `divot.outer`.
## At 12 m the ruin's band stops a clear ten metres short of that patch, so the
## pod's pose, the hatch the player stands in and every number
## `tests/TEST_escape_pod.gd` pins cannot see the ruin at all. The crater gets the
## same gap for symmetry; it is hundreds of metres away regardless.
@export var ruin_feature_gap := 12.0
## The most the levelling may move the ground anywhere under the footprint, in
## metres — core and band both. A candidate that needs more is discarded.
##
## "A CLEARING, NOT A QUARRY" IS THE REQUIREMENT AND THIS IS THE NUMBER. It is also
## what makes the tile corners safe BY CONSTRUCTION rather than by luck: see
## `ruin_slope_band`, where 3 m is the relief at which a corner 3.9 m into the band
## has moved 0.30 m, just inside the 0.385 m the apron stands proud. Raise this and
## that arithmetic has to be redone.
@export var ruin_earthwork_max := 3.0
## The most forest the site and the sight line from the start may carry, as a mean
## of `forest_at` over each, 0..1. A candidate over it is not discarded — it is kept
## as the FALLBACK, and used only if nothing open is found. See `_place_ruin`.
##
## "PUT IT IN A CLEARING" IS TAKEN LITERALLY. The pod came down in a wood and the
## island is mostly wood, so a site is either open ground that was already there or
## a hole cut in the forest — and a 28 m tower in a hole in a wood cannot be seen
## from anywhere but its own clearing. A quarter keeps the site and the line of
## sight to it genuinely open while tolerating the few trees at the pod's own edge
## of the wood, which the line has to cross on the shipped seed.
@export_range(0.0, 1.0) var ruin_open_forest := 0.25
## How far the ground in the clearing is worn to bare earth at full weight, 0..1.
## The build pads' `pad_grooming` construction, faded out across the band with the
## levelling itself, so the worn ground ends where the ground stops having been
## touched.
##
## OFF, BECAUSE THE GROUND HAS GROWN BACK. This shipped at 0.55 while the ruin stood
## in a clearing: earth with turf still in it, soil dominant out to about 30 m, a
## trodden ring round something very old. The island's vegetation now runs up to
## the stones and into the gaps between them (`docs/DOC_ruin_gap_growth.md`), and
## grass standing on worn earth read as exactly the ring it was meant to replace — a
## band of dry olive ground round a ruin the meadow had otherwise taken back. At 0
## the levelled disc is the meadow's own turf: grass 1.00 at the median and above
## 0.99 over 95% of it, down to 0.74 in one patch near the rim, where the open ground
## round it is 1.00 at the median and 0.66 at the tenth percentile. 0.55 is the old
## trodden look, and the wobble below still shapes it for any preset that wants it
## back.
@export_range(0.0, 1.0) var ruin_grooming := 0.0
## How far the worn ground's outline strays from the levelled disc, in units of the
## levelling weight, and the feature size of that wobble in metres.
##
## THE LEVELLING IS A DISC AND THE WEAR MUST NOT BE. The flat core is the model's
## circle to the millimetre, because that is what the apron needs; worn earth is
## where feet went, and nobody walks a compass circle. Rendered unwobbled the
## clearing came back from overhead as a perfect olive coin laid on the grass —
## the stamped read `sand_wobble` exists to break, for the same reason. So the
## weight the SPLAT grooms by is the levelling weight plus this much noise, which
## pushes the worn edge in and out across the band and leaves patches of turf in
## the core; the weight the SCATTERS clear by is untouched, so nothing grows back
## through the apron where the noise dips.
##
## THE NOISE NEVER REACHES PAST THE FOOTPRINT: it is added only where the levelling
## weight is above zero, so the look stays on ground the clearing actually touched.
##
## IT SHAPES NOTHING WHILE `ruin_grooming` IS 0, as it ships: there is no worn
## ground for it to move. The figures below are from when that was 0.55. Measured
## on the shipped site over 128 bearings, 0.35 of weight carries the
## soil-dominant edge anywhere from 25 m to 38 m out (10th to 90th percentile;
## median 30.5 m, against the 29.6 m it sits at unwobbled) and leaves turf on top
## over 27% of the core. 12 m features against an edge 30 m out lobe it several times
## round, and bring the turf in patches a few metres across — fine enough to read as
## wear rather than as a second shape, coarse enough to survive the 2 m vertex grid
## the splat is carried on.
@export_range(0.0, 1.0) var ruin_wear_wobble := 0.35
@export var ruin_wear_scale := 12.0

@export_subgroup("Ring")
## How many entrances, and so which layout. 0 is the ONE entrance `_place_ruin`
## searches for near the player start. N >= 1 is a RING: N entrances at even
## bearings round the island's centre, every door facing it. See
## `_place_ruin_ring`.
##
## EVERYTHING ELSE IN THIS GROUP STILL HOLDS ON A RING — `ruin_enabled`, the disc,
## the band, the coast margin, the zone rule, the gap kept to the crash site and the
## pod — except three things that are about the start: the walk band
## (`ruin_start_min`/`_max`), the walk's own zone rule and the openness gate. The
## earthwork cap is replaced rather than dropped; see `ruin_ring_earthwork_max`.
@export_range(0, 16) var ruin_ring_count := 0
## The ring's radius, as a fraction of the island's own: 0.64 is 800 m on the
## 1250 m hub.
##
## ON THE HUB IT IS PINNED FROM BOTH SIDES. The golf course and its banks keep a
## footprint's centre out past 740 m on some bearings, and the coast margin keeps it
## inside 730 m to 1110 m depending on the bearing, so a ring that is to stay off the
## course and on the plateau all the way round has little room to run in. 800 m is
## where the seven shipped bearings all find ground within 30 m of it;
## `tests/PROBE_ruin_ring.gd` sweeps 760 m to 840 m and at every one of them the
## furthest entrance ends up further off.
@export_range(0.05, 0.95) var ruin_ring_radius := 0.64
## The bearing of the first entrance, in degrees, in the field's own XZ frame: 0 is
## +X and 90 is +Z — so on a compass with north at -Z the first entrance stands at
## 90 plus this. The rest follow at 360/N.
##
## A SEARCHED NUMBER, NOT A STYLE CHOICE. The bearings are fixed once this is, and
## very few spins put every one of them within `ruin_ring_slide` of ground that can
## be levelled: on the shipped hub the crash site, the course and three hills leave
## one window for seven entrances 800 m out, from 0.50 to 1.00 degrees, and 0.75 is
## its middle and the spin in it that keeps every entrance nearest the ring. Retune
## the world and this is the number to search again; the probe prints the windows.
@export_range(-180.0, 360.0) var ruin_ring_spin := 0.0
## How far an entrance may move off the ring along its own bearing, in or out, to
## find ground the rules accept, in metres. See `_place_ruin_ring`: the bearing is
## never what gives, so the door always faces the centre square.
##
## A LIMIT, NOT A TARGET — the search stops at the nearest acceptable ground, and on
## the shipped hub nothing goes further than 30 m. It is there so that a retune
## which leaves a bearing with no ground near the ring loses that entrance instead of
## standing it on the far side of the course.
@export_range(0.0, 500.0) var ruin_ring_slide := 80.0
## The most the levelling may move the ground under a RING site, in metres — core and
## band both. `ruin_earthwork_max`'s job for sites whose bearing is fixed: a search
## that may look anywhere near the start can afford 3 m, and one that has to stand
## an entrance on one line of bearing cannot.
##
## 5.5 M, AND WHAT IT COSTS. The corner arithmetic under `ruin_slope_band` says a
## corner can rise a tenth of the relief, so 5.5 m allows 0.54 m in the worst case —
## past the 0.385 m the tiles stand proud. The worst case wants all the relief at a
## corner, and a hillside does not put it there: on the seven shipped sites no corner
## rises above 0.27 m. The price is the bank: on the five sites that need 4.5 m or
## more, the steepest levelled ground rises 0.42 to 0.47 in a metre — 23 to 25
## degrees, where the start-side cap keeps it near 13. A plain cut into the hill, and
## still turf: the rock rule and the canopy both wait for 45 degrees (0.29 in this
## file's 1 - n.y, against the 0.08 these banks reach), and a player walks up to 45.
## At the start-side cap of 3 m no spin stands all seven.
@export_range(0.0, 20.0) var ruin_ring_earthwork_max := 5.5

@export_group("Splat")
## Take the rock ramp from the slope VEGETATION gives out at, rather than from
## the hand-set pair below.
##
## Ground too steep to grow anything is a rock face, and that is one fact about
## the world rather than two numbers that happen to be near each other. Set as
## two numbers they drifted apart, and the gap between them was ground you could
## see: the canopy thins from `forest_max_slope * FOREST_SLOPE_KNEE` and is gone
## by 0.42, while rock did not begin until 0.42 and did not win until 0.68 — so
## every face between 55 and 72 degrees came out as bald bright turf with not a
## tree or a tuft standing on it.
##
## SMALL IN AREA, WHICH IS NOT THE SAME AS SMALL. `tests/PROBE_rock_veg.gd` puts
## the bald band at 2,922 m2 of the hub's 5.02 km2 — 0.058%. But a footprint
## measured flat under-reads a steep face by exactly the factor that makes it
## steep, and this is the one part of the island presented to the eye rather than
## to the map: 100% of the land past 0.42 was grass-dominant before and is
## rock-dominant after. Two thirds of it is zone banks (see `zone_skirt`, which
## is what keeps the new rock off the holes) and the rest is hill flank.
##
## With this on, `rock_slope_lo`/`_hi` are ignored and the band is
## `[forest_max_slope * FOREST_SLOPE_KNEE, forest_max_slope]` — see `rock_band`,
## which is what everything should ask rather than reading the exports.
##
## THE SCATTERS CLOSE THE LOOP, and it converges rather than running away. Both
## reject a cell whose dominant surface is rock, so moving the ramp down also
## pulls the effective vegetation ceiling down to where rock passes 0.5 — slope
## 0.357 rather than 0.42. That is the intended direction (no bald band is left
## over) and it stops there, because the splat reads slope alone and never reads
## back what grew.
##
## Turn it OFF to get the two dials back, e.g. for a world whose vegetation is
## switched off entirely.
@export var rock_follows_veg := true
## Slope at which rock starts and fully takes over (0 = flat, 1 = vertical).
## IGNORED unless `rock_follows_veg` is off.
##
## DEEPER THAN THEY WERE (0.30 / 0.55). At 0.30 the threshold sat below the
## gradient of an ordinary grassy hillside, so every flank in the world greyed
## over and rock stopped meaning "this is too steep to stand on". 0.42 is ~55
## degrees and 0.68 is ~72. Kept as the manual fallback because the pair is still
## the right shape — an onset and a saturation — it was just being tuned against
## the hills instead of against the vegetation.
@export_range(0.0, 1.0) var rock_slope_lo := 0.42
@export_range(0.0, 1.0) var rock_slope_hi := 0.68
## Distance, in metres, over which slope and curvature are measured. Kept
## independent of mesh resolution on purpose: if curvature were read off the
## vertex grid directly, a chunk would reclassify its surfaces the moment it
## changed LOD and you'd watch the texturing pop.
@export var curvature_radius := 4.0
## Curvature at which soil fully fills a hollow. Units are metres of rise per
## metre of sampling distance.
##
## STRICTER THAN IT WAS (0.30 / 0.40). The scale to judge these against is not
## the hills — it is the FINEST OCTAVE of them. A 4-octave fBm's top octave has a
## quarter of the feature size and an eighth of the amplitude, and curvature goes
## as amplitude / size squared, so the smallest wrinkles dominate the measurement
## by an order of magnitude over the landform. Measured on the shipped preset the
## typical magnitude is ~0.3, which the old thresholds treated as a gully and a
## crag: the result was the speckled grey-and-brown static that covered the wild
## ground. Set above that noise floor, the two rules go back to firing on real
## hollows and real spines.
@export var soil_concavity := 0.90
## Curvature at which rock is fully exposed on a ridge, on top of the slope rule.
@export var rock_convexity := 1.20
## Ceiling on how much rock the convexity rule alone may expose. The slope rule
## can still reach 1.0; this one is a dressing on top of it, so proud ground
## scours to a rocky streak rather than to a bare crag.
@export_range(0.0, 1.0) var rock_convex_gain := 0.50
## Width of the bare rock band around every coastline, in mask units. The shore
## ramp makes the ground dead flat at the cliff edge, so the slope rule alone
## would carpet the lip in grass — this exposes the rock the cliff is made of.
@export_range(0.0, 1.0) var coast_rock_width := 0.1

@export_group("Chunks")
## Depth of the vertical apron dropped at every chunk boundary, in metres.
##
## Chunks at different LODs sample the same edge at different densities, so the
## finer one's in-between vertices deviate from the coarser one's straight
## interpolation and leave a hairline gap. The skirt hangs below the boundary and
## covers it. It only has to exceed the worst-case deviation — roughly the local
## curvature over one coarse cell — so a few metres is ample. It is hidden inside
## the cliff cone from every angle you can actually get to.
@export var chunk_skirt_depth := 3.0

@export_group("Cliffs")
## Nominal drop from coastline to tip, as a MULTIPLE of the island's radius.
##
## Proportional rather than absolute, because a fixed depth cannot serve both
## sizes: 800 m under a 200 m satellite is a dramatic spike, and the same 800 m
## under the 1250 m hub is a shallow plate you look straight across. Scaling by
## radius keeps every island the same shape.
@export var cliff_depth_ratio := 4.0
@export var cliff_depth_min := 600.0

## World Y at which cliffs stop and cap off.
##
## Everything below the shader's `fog_bottom` renders as solid fog, so generating
## it is pure waste — and on the hub it is a LOT of waste, since a proportional
## depth would put its tip 5 km down and give every coastal chunk an AABB too
## tall to ever frustum-cull. Cutting here bounds the geometry and the bounds.
##
## THE INVARIANT: this must stay below the shader's `fog_bottom`, or you see the
## flat cap where the underside was sliced off. Default -600 against a -560 fog
## floor. It replaces the old "vertical_spread - cliff_depth < fog_bottom" rule,
## which depended on three numbers agreeing instead of one.
@export var cliff_cutoff_y := -600.0

# ---------------------------------------------------------------- the shoulder
#
# THE ROUNDED LIP BETWEEN THE PLATEAU AND THE WALL. Without it the coastline is a
# 90-degree corner: dead-level ground meets a sheer face in one edge, which is
# cheap and reads as a cake rather than as land. The shoulder replaces that
# corner with a band that leaves the shore at `cliff_shoulder_angle` and steepens
# asymptotically to vertical, so the island rounds over its own edge.
#
# THE CURVE IS AN EXPONENTIAL IN THE COTANGENT, which is worth stating because it
# is what makes "ever tapering angle that eventually goes full vertical" exact
# rather than approximate:
#
#     cot(theta(d)) = cot(theta_0) * exp(-d / L)          L = height / SPANS
#     r(d)          = r0 + S * (1 - exp(-d / L))          S = L * cot(theta_0)
#
# The angle approaches vertical and never reaches it, and dr/dd is positive and
# shrinking — so the lip FLARES, steadily and by less and less, until it is a
# wall.
#
# THE FLARE IS THE WHOLE POINT, and the sign is the one thing to get right. A
# surface that descends while moving inward is an UNDERCUT — its outer face
# points down, sees no sun, and renders blue under sky ambient. A fillet runs the
# other way: round over the edge of a cylinder and the arc goes from the top face
# down and OUT to meet the wall, radius growing with depth and the normal swinging
# from straight up to straight out. See `chunk_mesher._rim_profile`, which has the
# measurement that caught it.
#
# WHY THERE IS NO TANGENT MATCHING HERE, having looked for it: the plateau
# arrives at the coastline exactly flat, by construction and not by accident.
# `base_height` ramps the shore with a smoothstep, whose derivative is ZERO at
# both ends, and `shore_width` spreads that ramp over 0.22 of the mask — 275 m on
# the hub. Six metres inland the ground has risen about a centimetre. So there is
# no ground slope to match: matching it would set the shoulder's opening angle to
# a tenth of a degree and pull the lip hundreds of metres into the island. The
# opening angle is a chosen number instead, and the break it leaves at the rim is
# the price of keeping the coastline exactly where the rest of the world thinks
# it is. At 18 degrees against a plateau arriving at 0.1, that break is soft
# enough to read as a lip; the corner it replaces was 90.
#
## Metres from the shore line to where the lip is effectively vertical. Zero
## disables the shoulder entirely and restores the bare 90-degree rim.
##
## SIZED AGAINST THE CLOUD DECK, not against the island. `CloudSea.sea_altitude`
## is -45 and the shore is at 0, so the whole visible wall is a 45 m band; a
## shoulder much deeper than this one would still be curving when it reached the
## clouds and the island would lose its cliff entirely and read as a dome. At 20
## the lip takes the top of what you can see and leaves 25 m of unmistakable wall
## under it.
@export var cliff_shoulder_height := 20.0
## Angle the surface leaves the coastline at, degrees below horizontal.
##
## THE LOOK KNOB, and it trades two things against each other. Lower leaves the
## shore more nearly horizontally, so the break against the flat plateau is
## softer — but the flare is `height / SPANS * cot(angle)`, so it also throws the
## lip further out: 18 degrees puts the brim 21 m past the coastline and reads as
## a mushroom. Higher is a tighter brim and a sharper corner, walking back toward
## the 90 degrees this replaced. 26 gives a 10 m brim on a 20 m drop.
@export_range(4.0, 80.0) var cliff_shoulder_angle := 26.0
## Cap on how far the shoulder may flare, as a fraction of the island's radius.
##
## Binding on small islands and not on large ones, which is the point. The flare
## the angle asks for is absolute — about 10 m at 26 degrees — and 10 m on the
## hub's 1250 is nothing, while the same brim on an 85 m satellite would be an
## eighth of its width. Clamping here only ever makes a shoulder tighter and
## steeper, so the curve stays monotone and the sweep stays valid.
@export_range(0.0, 0.4) var cliff_shoulder_inset_max := 0.10
## Rings spent on the shoulder. This is the curve's whole geometry budget and it
## is the one place on the cliff where rings are always worth buying: every one
## of them lands in the band above the cloud deck.
@export var cliff_shoulder_rings := 5

## Terrace count down the underside.
@export var cliff_terraces := 5
## Vertical rings emitted per terrace -- the geometry budget for the cliff.
##
## 5 x 4 = 20 rings, against the 5 x 3 = 15 this started at. Almost all of the
## extra goes where it can be seen: SCENE_test_zone_W2 parks a cloud sea at
## y = -45 against a shore at y = 0, so the ENTIRE visible cliff is a 45 m band,
## and the old budget put about five rings in it. Twenty with `cliff_ring_bias` at
## 2.4 puts seven there — a wall with a profile rather than a few ledges — for a
## third fewer triangles than the 24 it briefly used.
##
## The bias is what makes that trade work, and it is the knob to reach for before
## this one: rings cost geometry all the way down a cone that is mostly under the
## clouds, the bias decides how much of it is spent above them.
@export var cliff_rings_per_terrace := 4
## Floor on wall rings, whatever `cliff_wall_rings_for` decides. Two is the
## geometric minimum for a quad strip; three leaves one interior ring so a wall
## that converges a little still bends rather than kinking.
@export_range(2, 12) var cliff_wall_rings_min := 3
## How many separately-culled vertical bands the wall is cut into.
##
## PURELY A CULLING KNOB — it changes no vertex position, only which mesh each
## one lands in. One band is the old behaviour: a single sweep whose AABB runs
## from the rim to the island's centre axis and hundreds of metres down, which is
## "visible" from nearly any angle and therefore submits the whole wall, fog
## floor included, whenever any part of the chunk is on screen. See
## `chunk_mesher._wall_bands` for why the bands are cut by equal ring count.
##
## Costs one draw call per band per coastal chunk, and a handful of duplicated
## vertices at each boundary ring. Four is the point where the deep bands start
## failing the frustum test from a standing eye on the island.
@export_range(1, 12) var cliff_wall_bands := 4
## How long the cliff stays near-vertical before tapering in. 1.0 is a straight
## cone (reads as an ice-cream cone hanging in the sky); higher values hold a
## proper cliff face under the plateau and move the taper down out of sight.
##
## THIS IS THE KNOB FOR "MORE VISIBLE CLIFF", not the material's alpha fade.
## Lengthening the fade so the wall survives further down does not show you more
## wall — it shows you the CONE, and the converging columns read as vertical
## curtains hanging under the island rather than as rock. The fade was hiding
## that, which is most of why it was set as short as it was. Raising the taper
## pushes the convergence deeper instead, so there is more actual wall for a
## longer fade to reveal. Move the two together or neither.
##
## At 3.4 the radius is still 98% of the coastline's 280 m down, against 93% at
## 2.2 — which is the difference between a face and a funnel.
@export_range(1.0, 4.0) var cliff_taper := 3.4
## Distribution of rings down the drop. Above 1.0 they bunch toward the top,
## which is the only part above the fog and therefore the only part you see.
@export_range(1.0, 3.0) var cliff_ring_bias := 2.4
## Per-position wobble on cliff depth, as a fraction of `cliff_depth`.
##
## Faded out toward the tip, so ALL of it lands in the top of the wall — which on
## a hub whose cone is truncated at the fog floor is the only part built, and the
## only part above the cloud deck. At 0.22 that read as an unsteady, lumpy rim
## rather than as rock; 0.10 keeps the wall irregular without making it look
## uncertain about where it is.
@export_range(0.0, 0.6) var cliff_depth_variance := 0.10
@export var cliff_noise_scale := 90.0

var _coast_noise: FastNoiseLite
var _hill_noise: FastNoiseLite
var _ridge_noise: FastNoiseLite
var _micro_noise: FastNoiseLite
var _sand_noise: FastNoiseLite
var _sand_wobble_noise: FastNoiseLite
var _crater_wobble_noise: FastNoiseLite
var _divot_wobble_noise: FastNoiseLite
var _ruin_wear_noise: FastNoiseLite
var _cliff_noise: FastNoiseLite
var _zone_noise: FastNoiseLite
var _green_noise: FastNoiseLite
var _forest_noise: FastNoiseLite
var _cells := {}    ## Vector2i cell -> Island or null (null = void cell).
var _ready := false
# The rock ramp `splat_weights` actually uses, resolved once in `prepare()`
# rather than per vertex. See `rock_follows_veg` and `rock_band`.
var _rock_lo := 0.0
var _rock_hi := 0.0
# The par system in force across the whole field: `golf_config` when one is
# assigned, otherwise the built-in one seeded from `par3_max`/`par4_max`.
# Resolved in `prepare()` for the same reason the rock ramp is -- so a retune is
# picked up at the one point everything else already agrees to re-read.
var _golf_config: GolfConfig = null


# Build the noise instances. Safe to call repeatedly; call again after changing
# `world_seed` or any *_scale so the noises pick the change up.
func prepare() -> void:
	_coast_noise = _make_noise(0x1001, FastNoiseLite.TYPE_SIMPLEX, coast_noise_scale, 3)
	_hill_noise = _make_noise(0x2002, FastNoiseLite.TYPE_SIMPLEX, hill_scale,
			maxi(hill_octaves, 1))
	_ridge_noise = _make_noise(0x3003, FastNoiseLite.TYPE_SIMPLEX, ridge_scale,
			maxi(ridge_octaves, 1))
	_ridge_noise.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_micro_noise = _make_noise(0x4004, FastNoiseLite.TYPE_SIMPLEX, micro_scale, 2)
	# Cellular, not simplex: `sand_at` needs distance-to-nearest-trap-centre, and
	# with RETURN_DISTANCE this is a true Euclidean distance field in units of
	# the cell size. Verified rather than assumed -- its gradient magnitude
	# measures 1.0000 at both the median and the 90th percentile, which is the
	# defining property, so the metres conversion in `sand_at` is exact.
	_sand_noise = _make_noise(0x5005, FastNoiseLite.TYPE_CELLULAR, sand_spacing, 1)
	_sand_noise.cellular_distance_function = FastNoiseLite.DISTANCE_EUCLIDEAN
	_sand_noise.cellular_return_type = FastNoiseLite.RETURN_DISTANCE
	_sand_noise.cellular_jitter = sand_jitter
	_sand_noise.fractal_type = FastNoiseLite.FRACTAL_NONE
	_sand_wobble_noise = _make_noise(0x500A, FastNoiseLite.TYPE_SIMPLEX,
			sand_wobble_scale, 2)
	# The crater's outline wobble. Its OWN noise rather than a second read of
	# `_sand_wobble_noise` at a different scale: the two run at 26 m and 31 m
	# features, close enough that sharing an instance would lock a crater's
	# lobes to the bunker field's and make the one visibly a scaled copy of the
	# other wherever they were near each other.
	_crater_wobble_noise = _make_noise(0x500C, FastNoiseLite.TYPE_SIMPLEX,
			crater_wobble_scale, 2)
	# The divot's outline wobble, and its own instance for the reason above — at
	# 7 m features it runs four times finer than the crater's, and sharing one
	# would make a 14 m dent and a 90 m crater visibly the same lobes at two
	# scales. One octave rather than two: at this size the second octave is
	# sub-vertex on every LOD rung the dent is legible at, so it is fetched and
	# then averaged straight back out by the mesh.
	_divot_wobble_noise = _make_noise(0x500D, FastNoiseLite.TYPE_SIMPLEX,
			divot_wobble_scale, 1)
	# The ruin's worn ground, on its own instance for the reason the crater's and
	# the divot's are: at 12 m it would otherwise share lobes with whichever of
	# those runs nearest that scale. See `ruin_wear_wobble`.
	_ruin_wear_noise = _make_noise(0x500E, FastNoiseLite.TYPE_SIMPLEX,
			ruin_wear_scale, 2)
	_cliff_noise = _make_noise(0x6006, FastNoiseLite.TYPE_SIMPLEX, cliff_noise_scale, 2)
	_zone_noise = _make_noise(0x7007, FastNoiseLite.TYPE_SIMPLEX, zone_noise_scale, 3)
	_green_noise = _make_noise(0x8008, FastNoiseLite.TYPE_SIMPLEX, green_scale, 2)
	# Two octaves, not three: a wood wants a broad, legible outline, and the
	# third octave only frays it into scattered copses.
	_forest_noise = _make_noise(0x9009, FastNoiseLite.TYPE_SIMPLEX, forest_scale, 2)
	var band := rock_band()
	_rock_lo = band.x
	_rock_hi = band.y
	_golf_config = _build_golf_config()
	# Islands cache their zones, so dropping the islands is also what drops the
	# stale zone layout after a parameter change -- and, since the narrowed golf
	# config is cached on the island beside them, the stale par markers too.
	_cells.clear()
	_ready = true


# An independent copy for a worker thread: same parameters and therefore exactly
# the same world, but its own noise objects and island cache.
func clone() -> IslandField:
	var f: IslandField = duplicate(true)
	f.prepare()
	return f


func _make_noise(salt: int, type: int, scale: float, octaves: int) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = world_seed ^ salt
	n.noise_type = type
	n.frequency = 1.0 / maxf(scale, 0.001)
	n.fractal_octaves = octaves
	return n


# The radius cap that keeps islands provably disjoint.
#
# This is load-bearing, not cosmetic. Two islands that touched would have to
# blend two different `base_y` values across one coastline, which tears the mesh
# — and the mesher relies on disjointness to build each island from its own disc
# alone, without consulting its neighbours.
#
# Centres are jittered inside the middle 30% of their cell, so two neighbouring
# centres are never closer than 0.7 * spacing. Coastline wobble can push a shore
# out to `radius * (1 + coast_irregularity)`, so the land discs stay disjoint iff
#
#     2 * max_radius * (1 + coast_irregularity)  <  0.7 * spacing
#
# The 0.34 (rather than 0.35) leaves a little slack on top of that bound.
func max_radius() -> float:
	return minf(maxf(satellite_radius_near, satellite_radius_far),
			island_spacing * 0.34 / (1.0 + coast_irregularity))


## The largest land radius anything in the world can have — satellites are capped
## by the lattice, but the hub is placed by hand and is not.
func world_max_radius() -> float:
	return maxf(max_radius(), hub_radius if hub_enabled else 0.0)


## The lattice cell the ANCHOR hub lives in. Every hub cell is this one offset by
## a whole multiple of `hub_lattice` on each axis.
func hub_cell() -> Vector2i:
	return Vector2i(floori(hub_center.x / island_spacing), floori(hub_center.y / island_spacing))


## Does a lattice cell carry a hub?
func is_hub_cell(cell: Vector2i) -> bool:
	if not hub_enabled:
		return false
	var lat := maxi(hub_lattice, 1)
	var d := cell - hub_cell()
	return posmod(d.x, lat) == 0 and posmod(d.y, lat) == 0


## Where the hub in a given hub cell sits.
##
## A whole-cell translation of `hub_center` rather than the cell's own centre, so
## every hub keeps the identical offset within its cell and the hub lattice is
## exactly the anchor repeated. That keeps `hub_center` meaning what it always
## meant — where the hub you spawn next to actually is.
func hub_center_for(cell: Vector2i) -> Vector2:
	var d := cell - hub_cell()
	return hub_center + Vector2(float(d.x), float(d.y)) * island_spacing


## Centre of the hub nearest an XZ point. Hubs are a regular lattice, so this is
## a rounding rather than a search.
func nearest_hub_center(p: Vector2) -> Vector2:
	var lat := maxi(hub_lattice, 1)
	var stride := float(lat) * island_spacing
	var hx := roundi((p.x - hub_center.x) / stride)
	var hz := roundi((p.y - hub_center.y) / stride)
	return hub_center + Vector2(float(hx), float(hz)) * stride


# ------------------------------------------------------------------ landmass

# The island (if any) seeded in a given lattice cell. Cached per instance.
#
# The hub simply replaces whatever its own cell would have rolled, which keeps
# every caller — streaming, meshing, point queries — on one uniform "ask the
# lattice" path instead of special-casing it everywhere.
func _cell_island(cell: Vector2i) -> Island:
	if _cells.has(cell):
		return _cells[cell]

	var isl: Island = null
	if is_hub_cell(cell):
		isl = Island.new()
		isl.cell = cell
		isl.center = hub_center_for(cell)
		isl.radius = hub_radius
		isl.is_hub = true
		if cell == hub_cell():
			# The anchor keeps its hand-authored altitude, so whatever the scene
			# spawns you next to is unchanged by hubs having become a lattice.
			isl.base_y = hub_base_y
			isl.peak = hub_peak
		else:
			var hrng := RandomNumberGenerator.new()
			hrng.seed = (cell.x * 83492791) ^ (cell.y * 12582917) ^ world_seed ^ 0x48085
			isl.base_y = hub_base_y + hrng.randf_range(-hub_base_spread, hub_base_spread)
			isl.peak = hub_peak * hrng.randf_range(0.8, 1.2)
		_cells[cell] = isl
		return isl

	var rng := RandomNumberGenerator.new()
	rng.seed = (cell.x * 73856093) ^ (cell.y * 19349663) ^ world_seed ^ 0x5AFE15
	# Jitter inside the middle 30% of the cell -- this is what guarantees the
	# 0.7 * spacing minimum separation that max_radius() relies on.
	var centre := Vector2(
		(float(cell.x) + rng.randf_range(0.35, 0.65)) * island_spacing,
		(float(cell.y) + rng.randf_range(0.35, 0.65)) * island_spacing)

	# Satellites shrink and thin with distance out from the NEAREST hub's rim, so
	# the composition reads as one landmass shedding debris rather than a uniform
	# field that happens to have a big island in it — and reads that way around
	# every hub, not just the anchor. Measured from the anchor alone, satellites
	# out near the next hub would arrive at their smallest and sparsest exactly
	# where a second landmass is rising out of the void.
	var t := 1.0
	if hub_enabled:
		t = clampf((centre.distance_to(nearest_hub_center(centre)) - hub_radius)
				/ maxf(satellite_reach, 1.0), 0.0, 1.0)
	if rng.randf() >= lerpf(satellite_density_near, satellite_density_far, t):
		_cells[cell] = null
		return null

	isl = Island.new()
	isl.cell = cell
	isl.center = centre
	isl.radius = minf(lerpf(satellite_radius_near, satellite_radius_far, t)
			* rng.randf_range(0.8, 1.2), max_radius())
	isl.base_y = rng.randf_range(-vertical_spread, vertical_spread)
	isl.peak = rng.randf_range(0.6, 1.4)

	# The lattice cap keeps satellites off each other, but nothing keeps them off
	# a HUB, which is far larger than a cell and so is not covered by the
	# spacing argument at all. Drop any that would land inside the clearance ring
	# of the nearest one — a satellite overlapping a hub would have to blend two
	# different base altitudes across one coastline and tear.
	#
	# The nearest hub suffices: every hub has the same radius, so the smallest
	# gap is always to the closest centre.
	if hub_enabled:
		var gap := centre.distance_to(nearest_hub_center(centre)) \
				- hub_radius * (1.0 + coast_irregularity + COAST_EPSILON) \
				- isl.radius * (1.0 + coast_irregularity + COAST_EPSILON)
		if gap < hub_clearance:
			isl = null

	_cells[cell] = isl
	return isl


## The island seeded in a lattice cell, or null if that cell is void.
func island_in_cell(cell: Vector2i) -> Island:
	if not _ready:
		prepare()
	return _cell_island(cell)


## Half-width of an island's footprint, coastline wobble included.
func island_extent(isl: Island) -> float:
	return isl.radius * (1.0 + coast_irregularity + COAST_EPSILON)


## Could an XZ rect hold any of this island's land? Conservative — it may say
## yes for a rect that turns out empty, never no for one that isn't. Lets the
## streamer skip the corner chunks of an island's bounding square without
## paying to mesh them first.
func rect_touches_island(isl: Island, min_x: float, min_z: float,
		max_x: float, max_z: float) -> bool:
	var outer := island_extent(isl)
	# Nearest point of the rect to the island centre.
	var nx := clampf(isl.center.x, min_x, max_x)
	var nz := clampf(isl.center.y, min_z, max_z)
	return Vector2(nx, nz).distance_squared_to(isl.center) <= outer * outer


## Could an XZ rect hold any COASTLINE, as opposed to lying wholly inland or
## wholly over the void? Also conservative.
##
## The per-chunk LOD scheduler leans on this: chunks that can contain coastline
## are pinned to a single shared LOD per island so the contour never disagrees
## across a chunk join, while chunks that are certainly inland are free to pick
## their own LOD and let a skirt cover the height mismatch.
func rect_touches_coast(isl: Island, min_x: float, min_z: float,
		max_x: float, max_z: float) -> bool:
	if not rect_touches_island(isl, min_x, min_z, max_x, max_z):
		return false
	var inner := isl.radius * (1.0 - coast_irregularity - COAST_EPSILON)
	if inner <= 0.0:
		return true
	# Farthest corner of the rect from the centre. If even that is inside the
	# inner radius the whole rect is solidly inland.
	var fx := maxf(absf(min_x - isl.center.x), absf(max_x - isl.center.x))
	var fz := maxf(absf(min_z - isl.center.y), absf(max_z - isl.center.y))
	return fx * fx + fz * fz > inner * inner


# Every island whose coastline could reach the given XZ rectangle. A superset is
# fine and is what callers want: the mesher passes one list for a whole chunk,
# and as long as it contains the true owner of every point in that chunk, the
# mask agrees exactly with what a per-point query would produce.
func islands_in_rect(min_x: float, min_z: float, max_x: float, max_z: float) -> Array:
	# Sized off the HUB when there is one: it lives in a single lattice cell but
	# spans many, so a rect out at its rim still has to scan far enough back to
	# find the cell that owns it.
	var reach := world_max_radius() * (1.0 + coast_irregularity + COAST_EPSILON)
	var c0 := Vector2i(floori((min_x - reach) / island_spacing), floori((min_z - reach) / island_spacing))
	var c1 := Vector2i(floori((max_x + reach) / island_spacing), floori((max_z + reach) / island_spacing))
	var out: Array = []
	for cz in range(c0.y, c1.y + 1):
		for cx in range(c0.x, c1.x + 1):
			var isl := _cell_island(Vector2i(cx, cz))
			if isl == null:
				continue
			# Reject islands whose own (wobble-expanded) disc misses the rect.
			var r := isl.radius * (1.0 + coast_irregularity + COAST_EPSILON)
			if isl.center.x + r < min_x or isl.center.x - r > max_x:
				continue
			if isl.center.y + r < min_z or isl.center.y - r > max_z:
				continue
			out.append(isl)
	return out


# The islands relevant to a single point (the 3x3 lattice neighbourhood, which
# is sufficient because max_radius() < island_spacing).
func islands_at(x: float, z: float) -> Array:
	return islands_in_rect(x, z, x, z)


## The island occupying a lattice cell, or null for a cell that rolled void.
##
## The lattice is this world's index -- a `Hole.id` and a `Hole.cell` both name a
## cell -- so this is the way BACK from a label to the island that carries it,
## which is otherwise a rect query around a point you would have to reconstruct.
func island_for_cell(cell: Vector2i) -> Island:
	if not _ready:
		prepare()
	return _cell_island(cell)


# The signed landmass field: > 0 on land, < 0 over void, 0 exactly on the
# coastline. Returns the owning island in `out_owner` (index 0) when one exists,
# which the height and cliff code needs for `base_y` and for the convergence axis.
#
# Value is `1 - distance/radius` for the nearest island, so it reads as
# "fraction of the way from coast to centre", plus a coastline wobble.
func mask_at(x: float, z: float, islands: Array, out_owner: Array = []) -> float:
	var best := -1e9
	var owner: Island = null
	var p := Vector2(x, z)
	for isl in islands:
		var i: Island = isl
		var v := 1.0 - i.center.distance_to(p) / i.radius
		if v > best:
			best = v
			owner = i
	if owner == null:
		if not out_owner.is_empty():
			out_owner[0] = null
		return -1.0
	if not out_owner.is_empty():
		out_owner[0] = owner
	# The wobble is added after the argmax. In the stock (positional) mode it is the
	# same for every island at a point, so this is exactly an in-loop add for less
	# work; in jagged mode it is the owner's angular wobble, which is the boundary
	# that actually decides this point's ownership since discs stay disjoint.
	return best + _coast_wobble(owner, x, z) * coast_irregularity


# The coastline wobble term for an island at a point, in units of
# `coast_irregularity` (i.e. multiply by it to get the mask contribution).
#
# Stock mode: 2D positional noise — a wobble that varies along the radial too, so a
# rim contour can pinch a fragment off the mainland or trap a pocket of void.
#
# Jagged mode: the noise is read around a circle indexed by the BEARING from the
# island centre, so it depends on angle alone. That makes the shore a single-valued
# radius R(angle) and the land the star domain {d <= R(angle)} — connected, hole-free
# and scatter-free no matter how deep the notches, which is the whole point. The
# circle is offset per cell so neighbouring islands don't share a silhouette, and it
# is sampled via cos/sin so it is seamless across the ±PI wrap.
func _coast_wobble(isl: Island, x: float, z: float) -> float:
	if not coast_jagged:
		return _coast_noise.get_noise_2d(x, z)
	var to_p := Vector2(x, z) - isl.center
	var ang := atan2(to_p.y, to_p.x)
	var ox := float(isl.cell.x) * 1000.0
	var oz := float(isl.cell.y) * 1000.0
	return _coast_noise.get_noise_2d(cos(ang) * coast_jag_scale + ox,
			sin(ang) * coast_jag_scale + oz)


# The mask due to ONE island. Because `max_radius()` keeps island land discs
# disjoint, any point where this is positive belongs to `isl` and to no other —
# which is what lets the mesher build an island in isolation.
## The nominal full-cone depth for an island, before the fog-floor cutoff.
func cliff_depth_for(isl: Island) -> float:
	return maxf(cliff_depth_min, isl.radius * cliff_depth_ratio)


## How far down an island's underside is actually built: the shorter of its full
## cone and the drop to `cliff_cutoff_y`.
func cliff_drop_for(isl: Island) -> float:
	return minf(cliff_depth_for(isl), maxf(isl.base_y - cliff_cutoff_y, 1.0))


## How many depth scales the shoulder runs before it is called vertical.
##
## Four, and the figure is the whole reason the handoff to the wall is invisible.
## The surface angle at `n` scales is `atan(1 / (cot(theta_0) * exp(-n)))`: three
## scales leaves it at 81 degrees against a wall that starts at exactly 90, which
## is a 9-degree shading break right where the two meshes and their two materials
## already meet. Four leaves 87, and the residual break is under the noise in the
## rock normal map. Five would buy a degree for a quarter more shoulder depth.
const SHOULDER_SPANS := 4.0


## The shoulder's shape for one island, as (depth scale, inset, handoff depth) —
## all metres. `y` is the horizontal distance the lip pulls in over its whole
## run, `z` is where the wall takes over. All three are zero when the shoulder is
## switched off, which is the signal the mesher tests.
##
## Radius-clamped per `cliff_shoulder_inset_max`; clamping the INSET rather than
## the angle is what keeps the curve valid, since a smaller `S` at the same `L`
## is simply a steeper start and the profile stays monotone.
func cliff_shoulder_for(isl: Island) -> Vector3:
	if cliff_shoulder_height <= 0.0 or isl == null:
		return Vector3.ZERO
	var l := cliff_shoulder_height / SHOULDER_SPANS
	var s := l / maxf(tan(deg_to_rad(clampf(cliff_shoulder_angle, 1.0, 89.0))), 1e-4)
	s = minf(s, isl.radius * maxf(cliff_shoulder_inset_max, 0.0))
	return Vector3(l, s, cliff_shoulder_height)


## Wall rings actually worth emitting for an island: the full budget scaled by
## how much its cone genuinely converges before `cliff_cutoff_y` slices it off.
##
## RINGS ARE ONLY WORTH BUYING WHERE THE PROFILE BENDS, and on the hub it does
## not bend at all. `cliff_taper` deliberately holds the wall vertical under the
## plateau and only closes it up hundreds of metres down — and the hub's underside
## is cut at the fog floor long before that, at t_end = 0.41, where the raw
## convergence is 5%. So its wall is, to within a few degrees, a straight vertical
## extrusion, and the twenty rings it used to get were twenty copies of the same
## ring: 102,746 triangles across the streamed hub to describe a shape that four
## rings describe exactly as well.
##
## A satellite is the opposite case. Its cone fits above the cutoff, t_end is 1,
## it converges the whole way to a point, and it needs every ring in the budget.
## Interpolating on the convergence covers both without a special case.
##
## PER ISLAND, never per column, and that is a correctness requirement rather
## than a saving: neighbouring columns must agree on how many rings they have or
## the wall between them is not a quad strip. This depends only on the island's
## radius and altitude, so every column of it gets the same answer.
func cliff_wall_rings_for(isl: Island) -> int:
	var full := maxi(cliff_terraces, 1) * maxi(cliff_rings_per_terrace, 2)
	var lo := clampi(cliff_wall_rings_min, 2, full)
	if isl == null:
		return full
	var depth := cliff_depth_for(isl)
	var drop := cliff_drop_for(isl)
	var t_end := 1.0
	if drop < depth:
		t_end = pow(clampf(drop / depth, 0.0, 1.0), 1.0 / cliff_ring_bias)
	# RAW convergence, deliberately not run through `_terraced`. The staircase
	# rounds the hub's 5% down to a flat zero, and a zero here would claim the
	# wall is perfectly straight and hide the lean it does have.
	var conv := pow(t_end, cliff_taper)
	return clampi(int(round(lerpf(float(lo), float(full), conv))), lo, full)


## Per-position wobble applied to cliff depth, in 0..1 of `cliff_depth_variance`.
func cliff_wobble(x: float, z: float) -> float:
	return _cliff_noise.get_noise_2d(x, z) * cliff_depth_variance


func mask_for(isl: Island, x: float, z: float) -> float:
	return (1.0 - isl.center.distance_to(Vector2(x, z)) / isl.radius
			+ _coast_wobble(isl, x, z) * coast_irregularity)


# --------------------------------------------------------------------- zones

## Radius of the disc a zone must fit inside, in metres.
##
## A zone has to stay `zone_coast_margin` inland IN MASK UNITS, but it is placed
## in metres, so the conversion has to assume the worst the coastline wobble can
## do. The mask is `1 - d/R + wobble * coast_irregularity`, and the wobble bottoms
## out at -1, so `mask >= margin` is guaranteed everywhere only when
##
##     d <= R * (1 - zone_coast_margin - coast_irregularity)
##
## Conservative on purpose: the wobble is 3-octave simplex and rarely approaches
## its bound, so this reserves more shore than it strictly needs. Losing a little
## placeable area is the cheap failure; a fairway hanging over a cliff is not.
func _zone_safe_radius(isl: Island) -> float:
	return isl.radius * (1.0 - zone_coast_margin - coast_irregularity)


## Clear ground demanded between two zones on this island, in metres. See
## `zone_separation_ratio` for why this cannot be a constant.
func zone_gap_for(isl: Island) -> float:
	return minf(zone_separation, _zone_safe_radius(isl) * zone_separation_ratio)


## Bank width for a zone of a given half-width, in metres — proportional, capped
## and floored. See `zone_apron_ratio` and `zone_apron_min` for why it is all
## three at once.
func zone_apron_for(width: float) -> float:
	return minf(zone_apron, maxf(zone_apron_min, width * zone_apron_ratio))


# Does this island carry a course at all? Build pads are unaffected — satellites
# still get their flat cleared ground, they just do not get golf.
func _island_plays_golf(isl: Island) -> bool:
	if golf_hub_only and not isl.is_hub:
		return false
	return isl.radius >= golf_min_radius


## The zones carved into an island, built on first use and cached on it.
##
## Threading note: this mutates the `Island`, which is fine for exactly the
## reason the `_cells` cache is fine -- every worker holds its own `clone()`, and
## the sampler is seeded from the island's cell and `world_seed` alone, so every
## thread independently derives the identical layout.
func zones_for(isl: Island) -> Array:
	if isl == null:
		return []
	if not _ready:
		prepare()
	if isl.zones == null:
		isl.zones = _place_zones(isl)
		isl.holes = _label_holes(isl)
	return isl.zones


## The playable holes on an island, in index order. Empty for an island too
## small to hold one.
func holes_for(isl: Island) -> Array:
	if isl == null:
		return []
	zones_for(isl)
	return isl.holes


# Seeded rejection sampling: propose a capsule, reject it if it leaves the safe
# disc or crowds a zone already placed, keep it otherwise.
#
# Rejection sampling rather than a lattice or a Poisson-disc pass because the
# acceptance test is the interesting part. A hole has to satisfy two conditions
# that are awkward to satisfy by construction -- fit wholly inside a disc it is
# nearly as long as, and hold `zone_separation` from capsules at arbitrary
# angles -- and both are trivial to TEST. The attempt budget bounds the cost, and
# the layout is fully determined by the seed, so every thread and every revisit
# agrees without anything being stored.
func _place_zones(isl: Island) -> Array:
	var out: Array = []
	if not zone_enabled:
		return out
	var safe_r := _zone_safe_radius(isl)
	if safe_r <= 0.0:
		return out

	var rng := RandomNumberGenerator.new()
	rng.seed = (isl.cell.x * 40503) ^ (isl.cell.y * 30011) ^ world_seed ^ 0x60F20E

	var usable := PI * safe_r * safe_r
	var want_gap := zone_gap_for(isl)

	# ---- golf holes ------------------------------------------------------
	# Count comes from area, so it scales with the island: the hub carries a
	# course and a small satellite carries one hole, from one rule rather than
	# from a table of special cases.
	#
	# The length band is narrowed to what THIS island can hold before the count
	# is derived from it, and that ordering is load-bearing. Sizing the footprint
	# from the global 180-450 m band instead makes a small island's holes look
	# far more expensive than the ones it will actually place, so the count
	# rounds to zero and the island comes out bare -- while still being perfectly
	# able to hold the short par 3 the sampler would have proposed.
	var span_hi := 2.0 * (safe_r - hole_width_min * (1.0 + zone_irregularity))
	var len_hi := minf(hole_length_max, span_hi)
	var len_lo := minf(hole_length_min, len_hi)
	var want_holes := 0
	if _island_plays_golf(isl) and len_hi >= hole_length_floor:
		var mid_len := (len_lo + len_hi) * 0.5
		var mid_w := clampf(mid_len * hole_width_ratio, hole_width_min, hole_width_max)
		var hole_footprint := maxf(2.0 * mid_w * mid_len + PI * mid_w * mid_w, 1.0)
		want_holes = clampi(int(round(usable * golf_area_fraction / hole_footprint)),
				0, maxi(holes_max, 0))
	var placed := 0
	for _attempt in range(maxi(zone_place_attempts, 1) * maxi(want_holes, 1)):
		if placed >= want_holes:
			break
		var want_len := rng.randf_range(len_lo, len_hi)
		var w := clampf(want_len * hole_width_ratio, hole_width_min, hole_width_max)
		# `span_hi` was computed against the NARROWEST fairway, so a wide one
		# still has to be re-checked against its own girth.
		want_len = minf(want_len, 2.0 * (safe_r - w * (1.0 + zone_irregularity)))
		if want_len < hole_length_floor:
			break   # nothing shorter will fit either; stop burning attempts
		w = clampf(want_len * hole_width_ratio, hole_width_min, hole_width_max)

		var ang := rng.randf() * TAU
		var dir := Vector2(cos(ang), sin(ang))
		# Midpoint uniform BY AREA over the safe disc (hence the sqrt), or holes
		# would bunch toward the island's centre.
		var mang := rng.randf() * TAU
		var mid := isl.center + Vector2(cos(mang), sin(mang)) * (safe_r * sqrt(rng.randf()))

		# Trim the hole to the longest capsule that fits at THIS midpoint and
		# angle, rather than proposing a length and rejecting what does not fit.
		#
		# Rejection is hopeless here, and quietly so. `span_hi` is the longest
		# hole the island can hold anywhere, and it is only attainable through the
		# exact centre -- so a length near that bound is accepted only by a
		# candidate that is centred and aligned to within metres, which random
		# proposals essentially never are. Small islands ended up with no golf at
		# all while every attempt failed a test they could not have passed.
		var half := _max_half_length(isl.center, mid, dir,
				safe_r - w * (1.0 + zone_irregularity))
		want_len = minf(want_len, 2.0 * half)
		if want_len < hole_length_floor:
			continue
		# Re-derived width can only shrink, which only widens the disc the
		# capsule had to fit inside, so the trim above stays valid.
		w = clampf(want_len * hole_width_ratio, hole_width_min, hole_width_max)

		var a := mid - dir * (want_len * 0.5)
		var b := mid + dir * (want_len * 0.5)

		# ---- bend it ------------------------------------------------------
		# The straight capsule above is the SPINE the dogleg is derived from, and
		# deriving rather than proposing is the point: the straight fit already
		# solved "a corridor of this length, at this angle, fits this island", so
		# the bend only has to stay inside what that established.
		#
		# The elbow is pushed off the spine perpendicular; the two legs then run
		# tee -> elbow -> pin. Offsetting by `tan(turn / 2)` times the half-span is
		# what makes the DEFLECTION at the elbow come out at `turn` exactly, which
		# is the angle the export is written in terms of. A random offset would
		# have given a random turn and no way to ask for 45-75.
		var turn := deg_to_rad(rng.randf_range(
				minf(dogleg_angle_min, dogleg_angle_max),
				maxf(dogleg_angle_min, dogleg_angle_max)))
		var split := rng.randf_range(dogleg_split_min, dogleg_split_max)
		var elbow_t := a.lerp(b, split)
		var off := _dogleg_offset(want_len, split, turn)
		var perp := Vector2(-dir.y, dir.x)

		# THE BEND IS A REQUIREMENT, NOT A BEST EFFORT: a hole that cannot dogleg
		# here is not placed straight, it is not placed at all, and the attempt
		# loop tries somewhere else. Falling back to a straight capsule is what an
		# earlier version did, and it produced a course that was eight doglegs and
		# one driving range — which an average over the course hides completely.
		#
		# The elbow swings off the spine, so it is the one point of the three that
		# can leave the island. Rather than pull it back — which shallows the turn
		# and silently lands outside the requested band — try the OTHER side first.
		# The spine is already known to fit, so at least one of the two offsets is
		# almost always inside, and swapping sides costs nothing and keeps the
		# angle exact.
		var reach := w * (1.0 + zone_irregularity)
		var elbow_room := safe_r - reach
		var first := 1.0 if rng.randf() < 0.5 else -1.0
		var m_pt := Vector2.ZERO
		var bent := false
		for side in [first, -first]:
			var cand: Vector2 = elbow_t + perp * (off * side)
			if isl.center.distance_to(cand) > elbow_room:
				continue
			if a.distance_to(cand) < dogleg_leg_min \
					or cand.distance_to(b) < dogleg_leg_min:
				continue
			m_pt = cand
			bent = true
			break
		if not bent:
			continue

		if not _capsule_inside(isl.center, a, b, w, safe_r):
			continue
		if not _zone_clear_polyline([[a, m_pt], [m_pt, b]], w, out, want_gap):
			continue

		var zn := Zone.new()
		zn.a = a
		zn.b = b
		zn.m = m_pt
		zn.bent = true
		zn.width = w
		zn.kind = ZONE_GOLF
		# Recessed by `golf_inset`, so the hole sits in the land rather than on it.
		zn.lift = rng.randf_range(-zone_lift_spread, zone_lift_spread) - golf_inset
		zn.lift_b = zn.lift     # a fairway is a shelf: level end to end
		zn.apron = zone_apron_for(w)
		# Golf only. A build pad wants its bank to start at its edge -- the pad IS
		# the flat ground and widening it just eats the island -- and a path is 4 m
		# wide with a 9 m apron, so a 16 m collar would be four times the track.
		zn.skirt = maxf(zone_skirt, 0.0)
		placed += 1
		zn.index = placed
		out.append(zn)

	# ---- build pads ------------------------------------------------------
	# Placed AFTER the holes and tested against them, so golf wins every contest
	# for space and pads fill what is left between the holes and the hills.
	# Same ordering rule as the holes: narrow the radius band to this island
	# first, then let the count follow from it.
	var pad_hi := minf(build_pad_radius_max, safe_r * build_pad_radius_ratio)
	var pad_lo := minf(build_pad_radius_min, pad_hi)
	var mid_pad := (pad_lo + pad_hi) * 0.5
	var pad_footprint := maxf(PI * mid_pad * mid_pad, 1.0)
	var want_pads := 0
	if pad_hi >= build_pad_radius_min * 0.5:
		want_pads = clampi(int(round(usable * build_area_fraction / pad_footprint)),
				0, maxi(build_pads_max, 0))
	var pads := 0
	for _attempt in range(maxi(zone_place_attempts, 1) * maxi(want_pads, 1)):
		if pads >= want_pads:
			break
		var pr := rng.randf_range(pad_lo, pad_hi)
		var pang := rng.randf() * TAU
		var c := isl.center + Vector2(cos(pang), sin(pang)) * (safe_r * sqrt(rng.randf()))
		# (a square reaches its corners: room for those, not just its sides)
		var reach := pr * (1.42 if square_pads else 1.0)
		if not _capsule_inside(isl.center, c, c, reach, safe_r):
			continue
		if not _zone_clear(c, c, reach, out, want_gap):
			continue

		var pad := Zone.new()
		pad.a = c
		pad.b = c
		pad.width = pr
		pad.kind = ZONE_BUILD
		pad.lift = rng.randf_range(-zone_lift_spread, zone_lift_spread)
		pad.lift_b = pad.lift
		pad.apron = zone_apron_for(pr)
		if square_pads:
			pad.square = true
			pad.street = path_width
			pad.apron = maxf(square_apron, 0.1)
			# (the sides run along the line to the nearest zone already placed,
			# or anywhere: corrected below once all the pads are down)
			pad.rot = rng.randf() * TAU
		pads += 1
		pad.index = pads
		out.append(pad)

	# A SQUARE TOWN faces its nearest neighbour: its sides run along the line
	# to the nearest other zone, so the first road out of it runs straight
	# down one of its streets
	if square_pads:
		for entry in out:
			var zn: Zone = entry
			if not zn.square:
				continue
			var near := Vector2.INF
			for other in out:
				if other != zn and zn.a.distance_to((other.a + other.b) * 0.5) < zn.a.distance_to(near):
					near = (other.a + other.b) * 0.5
			if near != Vector2.INF:
				zn.rot = (near - zn.a).angle()

	# ---- paths -----------------------------------------------------------
	# Built LAST and from a snapshot of everything above, so they can be routed
	# against a layout that is already final. They are appended after it for the
	# same reason: `zone_at` breaks ties by array order, so a hole or a pad always
	# wins the ground it shares with the track running onto it, and "which hole am
	# I on" keeps the unambiguous answer the whole labelling scheme rests on.
	if path_enabled and out.size() >= 2:
		out.append_array(_place_paths(isl, out, rng, safe_r))

	return out


# ------------------------------------------------------------------- paths

# Join every zone on an island into one connected network of graded tracks.
#
# TOPOLOGY IS A MINIMUM SPANNING TREE over the zone centres. Not "every pair"
# (that is a road network, not a course, and n^2 tracks would flatten more ground
# than the zones they connect), and not "a chain" (whose total length is
# unbounded and which routes you through hole 5 to get from 4 to 6). An MST is
# the shortest set of links that leaves nothing stranded, which is exactly the
# brief. n is at most a couple of dozen, so the naive O(n^3) Prim below costs
# nothing and runs once per island.
#
# EACH LINK IS TWO CAPSULES, not one. A single straight capsule between two
# shelves is a cutting: it holds one straight grade and whatever hill lies
# between gets sliced through it. Bending the link at a waypoint whose own shelf
# altitude IS the terrain height there lets the track climb with the ground, and
# choosing that waypoint by how little earth the two halves move (`_path_cut`)
# makes paths route around hills rather than through them — with no search, no
# routing pass and nothing stored.
func _place_paths(isl: Island, zones: Array, rng: RandomNumberGenerator,
		safe_r: float) -> Array:
	var out: Array = []
	var n := zones.size()
	if n < 2:
		return out

	var centres: Array[Vector2] = []
	for entry in zones:
		var zn: Zone = entry
		centres.append((zn.a + zn.b) * 0.5)

	# Prim's, grown from zone 0: repeatedly take the cheapest edge from the tree to
	# anything still outside it. `links` accumulates those edges as (in-tree,
	# newly-added) index pairs, which is exactly the list of tracks to build.
	var in_tree := PackedInt32Array([0])
	var rest := PackedInt32Array()
	for i in range(1, n):
		rest.append(i)
	var links: Array = []
	while not rest.is_empty():
		var best_d := 1e30
		var best_i := 0
		var best_k := 0
		for i in in_tree:
			for k in range(rest.size()):
				var d := centres[i].distance_squared_to(centres[rest[k]])
				if d < best_d:
					best_d = d
					best_i = i
					best_k = k
		var j: int = rest[best_k]
		rest.remove_at(best_k)
		in_tree.append(j)
		links.append([best_i, j])

	# The disc a path's own rim has to stay inside, which is tighter than the one
	# the zones themselves fit in by exactly the track's wobbled girth.
	var track_r := maxf(safe_r - path_width * (1.0 + zone_irregularity), 1.0)
	var samples := maxi(path_grade_samples, 2)
	var index := 0

	for link in links:
		var za: Zone = zones[link[0]]
		var zb: Zone = zones[link[1]]
		# Start and end ON THE RIMS the track is joining, not at the centres: a
		# path that ran to the middle of a fairway would bulldoze a stripe down it.
		var pa := _clamp_to_disc(isl.center, _zone_port(za, centres[link[1]]), track_r)
		var pb := _clamp_to_disc(isl.center, _zone_port(zb, centres[link[0]]), track_r)
		var axis := pb - pa
		var span := axis.length()
		if span < path_width * 2.0:
			# Two zones whose rims already meet: a track between them is noise. In
			# practice unreachable — `zone_separation` guarantees 165 m of clear
			# ground between any two — so this is a guard against a preset that
			# turns that off rather than a case the world produces.
			continue
		var dir := axis / span
		var perp := Vector2(-dir.y, dir.x)
		var mid := (pa + pb) * 0.5

		var best_w := mid
		var best_lift := _ground_lift(isl, mid)
		var best_score := 1e30
		for c in range(maxi(path_waypoint_tries, 1)):
			# Candidate 0 is always the straight line, so a link across level
			# ground is never bent for the sake of it.
			var w := mid
			if c > 0:
				w = mid + perp * ((rng.randf() * 2.0 - 1.0) * path_waypoint_spread * span) \
						+ dir * ((rng.randf() - 0.5) * 0.3 * span)
				w = _clamp_to_disc(isl.center, w, track_r)
			var lw := _ground_lift(isl, w)
			var score := _path_cut(isl, pa, za.lift, w, lw, samples) \
					+ _path_cut(isl, w, lw, pb, zb.lift, samples)
			if score < best_score:
				best_score = score
				best_w = w
				best_lift = lw

		index += 1
		out.append(_make_path(pa, best_w, za.lift, best_lift, index))
		out.append(_make_path(best_w, pb, best_lift, zb.lift, index))

	return out


func _make_path(a: Vector2, b: Vector2, lift_a: float, lift_b: float,
		index: int) -> Zone:
	var zn := Zone.new()
	zn.a = a
	zn.b = b
	zn.width = path_width
	zn.kind = ZONE_PATH
	zn.lift = lift_a
	zn.lift_b = lift_b
	zn.apron = path_apron
	zn.index = index
	return zn


# The point on a zone's rim that faces `t`: the nearest point of its axis, pushed
# out by its own half-width. Un-wobbled on purpose -- the wobble is a property of
# the ground, and a port derived from it would move whenever `zone_irregularity`
# was retuned while the track it anchors did not.
static func _zone_port(zn: Zone, t: Vector2) -> Vector2:
	# A SQUARE's ports are the ends of its two streets, the middle of each
	# side: the one facing `t` most nearly
	if zn.square:
		var best := zn.a
		var most := -INF
		for k in 4:
			var dir := Vector2.RIGHT.rotated(zn.rot + k * PI * 0.5)
			var f := dir.dot((t - zn.a).normalized())
			if f > most:
				most = f
				best = zn.a + dir * zn.width
		return best
	var ab := zn.b - zn.a
	var d2 := ab.length_squared()
	var q := zn.a
	if d2 >= 1e-9:
		q = zn.a + ab * clampf((t - zn.a).dot(ab) / d2, 0.0, 1.0)
	var d := t - q
	if d.length_squared() < 1e-9:
		return q
	return q + d.normalized() * zn.width


static func _clamp_to_disc(center: Vector2, p: Vector2, r: float) -> Vector2:
	var d := p - center
	var len := d.length()
	if len <= r or len < 1e-9:
		return p
	return center + d * (r / len)


## Wild-ground height at a point, as a shelf lift relative to the island's
## `base_y` -- i.e. in the same units `Zone.lift` is in.
##
## Exact rather than approximate because paths live wholly inside the safe disc,
## where the shore ramp is saturated at 1 and `base_height` is just
## `base_y + ground`. A path allowed onto the ramp would break that.
func _ground_lift(isl: Island, p: Vector2) -> float:
	return base_height(p.x, p.y, mask_for(isl, p.x, p.y), isl) - isl.base_y


# How much earth one half-link moves: the mean absolute gap between the wild
# ground and the straight grade the track would hold across it. Mean rather than
# max because a single hummock should not veto an otherwise level route, and one
# deep notch crossed at right angles costs less to bridge than a whole flank cut
# lengthwise.
func _path_cut(isl: Island, p0: Vector2, l0: float, p1: Vector2, l1: float,
		samples: int) -> float:
	var acc := 0.0
	for i in range(samples):
		var t := float(i + 1) / float(samples + 1)
		var p := p0.lerp(p1, t)
		acc += absf(_ground_lift(isl, p) - lerpf(l0, l1, t))
	return acc / float(samples)


# Longest half-length a segment through `mid` in direction `dir` can have while
# both endpoints stay inside a disc of radius `r` about `center`.
#
# Solves |mid + L*dir - center| <= r for L, taking the endpoint that leaves the
# disc first. Expanding gives L^2 + 2L*(d . dir) + |d|^2 - r^2 <= 0 with
# d = mid - center; using |d . dir| covers both endpoints at once, so the
# positive root of that quadratic is the answer.
static func _max_half_length(center: Vector2, mid: Vector2, dir: Vector2,
		r: float) -> float:
	if r <= 0.0:
		return 0.0
	var d := mid - center
	var proj := absf(d.dot(dir))
	var disc := proj * proj - d.length_squared() + r * r
	if disc <= 0.0:
		return 0.0   # the midpoint itself is already outside
	return maxf(sqrt(disc) - proj, 0.0)


# Does a capsule lie wholly inside the island's safe disc?
#
# Exact, not conservative: a capsule is a segment grown by `width`, and the
# farthest point of a segment from any external point is one of its endpoints,
# so checking both endpoints plus the (wobble-expanded) girth is the whole test.
func _capsule_inside(center: Vector2, a: Vector2, b: Vector2, w: float,
		safe_r: float) -> bool:
	var reach := w * (1.0 + zone_irregularity)
	return (center.distance_to(a) + reach <= safe_r
			and center.distance_to(b) + reach <= safe_r)


# Is a proposed capsule far enough from every zone already placed?
#
# The gap is measured between the WOBBLED boundaries, so `zone_separation` is
# the clear ground that survives the worst the lobe noise can do -- which is what
# makes "a point belongs to at most one zone" a guarantee rather than a hope.
func _zone_clear(a: Vector2, b: Vector2, w: float, placed: Array,
		want_gap: float) -> bool:
	return _zone_clear_polyline([[a, b]], w, placed, want_gap)


# The same test for an axis of one OR two segments. Every pair of segments has to
# clear, so a dogleg's elbow cannot swing into a neighbouring fairway even when
# both its endpoints are comfortably distant — which a straight-line test between
# endpoints would have missed entirely, and silently.
func _zone_clear_polyline(segs: Array, w: float, placed: Array,
		want_gap: float) -> bool:
	var reach := w * (1.0 + zone_irregularity)
	for other in placed:
		var o: Zone = other
		var limit := want_gap + reach + o.width * (1.0 + zone_irregularity)
		for s in segs:
			for t in o.segments():
				if _segment_gap(s[0], s[1], t[0], t[1]) < limit:
					return false
	return true


# How far to push a dogleg's elbow off the tee-to-pin spine so that the
# DEFLECTION between the two legs comes out at exactly `turn` radians.
#
# Solved rather than approximated, because the obvious approximation is wrong
# everywhere except the middle. Offsetting by `min(p, 1-p) * L * tan(turn/2)`
# gives exactly `turn` when the elbow is halfway along and progressively less as
# it moves toward either end — at split 0.35 it delivers 35 degrees for a
# requested 45, which is how a hole ends up outside a band it was constructed to
# sit inside.
#
# With p the split, q = 1 - p and u the offset as a fraction of the spine length,
# the two legs make angles atan(u/p) and atan(u/q) with the spine, so
#
#     tan(turn) = (u/p + u/q) / (1 - u^2/(pq)) = u / (pq - u^2)      [p + q = 1]
#
# which is a quadratic in u. The positive root is the offset.
static func _dogleg_offset(length: float, split: float, turn: float) -> float:
	var p := clampf(split, 0.01, 0.99)
	var pq := p * (1.0 - p)
	# At exactly 90 degrees the tangent is undefined and the root tends to
	# sqrt(pq); clamping just below keeps one expression for the whole range.
	var t := tan(clampf(turn, 0.0, deg_to_rad(89.0)))
	if t <= 1e-6:
		return 0.0
	return length * (-1.0 + sqrt(1.0 + 4.0 * t * t * pq)) / (2.0 * t)


# Minimum distance between two 2D segments. Crossing segments are distance zero;
# otherwise the minimum is attained at an endpoint of one of them, so the four
# point-to-segment distances cover every case.
static func _segment_gap(a0: Vector2, a1: Vector2, b0: Vector2, b1: Vector2) -> float:
	if _segments_cross(a0, a1, b0, b1):
		return 0.0
	return minf(minf(_point_seg_dist(a0, b0, b1), _point_seg_dist(a1, b0, b1)),
			minf(_point_seg_dist(b0, a0, a1), _point_seg_dist(b1, a0, a1)))


static func _point_seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var d2 := ab.length_squared()
	if d2 < 1e-9:
		return p.distance_to(a)
	return p.distance_to(a + ab * clampf((p - a).dot(ab) / d2, 0.0, 1.0))


# Strict crossing test by the sign of the four orientation determinants.
# Collinear and endpoint-touching cases deliberately fall through to the
# distance path above, which returns ~0 for them anyway.
static func _segments_cross(a0: Vector2, a1: Vector2, b0: Vector2, b1: Vector2) -> bool:
	var d1 := (a1 - a0).cross(b0 - a0)
	var d2 := (a1 - a0).cross(b1 - a0)
	var d3 := (b1 - b0).cross(a0 - b0)
	var d4 := (b1 - b0).cross(a1 - b0)
	return (d1 > 0.0) != (d2 > 0.0) and (d3 > 0.0) != (d4 > 0.0)


func _label_holes(isl: Island) -> Array:
	var cfg := golf_config_for(isl)
	var out: Array = []
	for entry in isl.zones:
		var zn: Zone = entry
		if zn.kind != ZONE_GOLF:
			continue
		var h := Hole.new()
		h.index = zn.index
		h.cell = isl.cell
		h.id = "%d:%d:%d" % [isl.cell.x, isl.cell.y, zn.index]
		h.tee = zn.a
		h.pin = zn.b
		h.width = zn.width
		h.length = zn.length()
		# The elbow comes across with the endpoints rather than being looked up
		# later. This is the one place a Hole and its Zone are both in hand, and a
		# caller holding only a Hole has no way back to the Zone that made it.
		h.bend = zn.m
		h.bent = zn.bent
		# Both from the SAME config object, so the par and the story about where
		# it came from cannot be answers to two different questions.
		h.par = cfg.par_for(isl.cell, h.index, h.length)
		h.par_source = cfg.par_source(isl.cell, h.index, h.length)
		out.append(h)
	return out


## The mown-lawn weight for a golf zone's flatten weight: see `golf_groom_lo`.
## Kept here rather than in the mesher so the field stays the single authority on
## what the ground IS, and so a gameplay query and the vertex under it cannot
## disagree about where the fairway is mown.
func golf_groom(zone_flat: float) -> float:
	return smoothstep(golf_groom_lo, maxf(golf_groom_hi, golf_groom_lo + 1e-4),
			zone_flat)


## Par for a tee-to-pin distance alone, with no hole to hang a marker on: the
## MAKER, and then the global default if the maker declines. Kept as a function
## in its own right because "what would a hole this long score" is a fair
## question to ask the field without placing one.
##
## Behaviour changed in one place only, and it is the place the default was added
## for: a hole longer than `GolfConfig.par5_max` used to come back as a par 5 and
## now comes back as `default_par`. Nothing in the shipped tuning is that long.
func par_for_length(length: float) -> int:
	var cfg := global_golf_config()
	var made := cfg.par_from_length(length)
	return cfg.clamp_par(made if made > 0 else cfg.default_par)


## The par system in force across the whole field. Never null: an unassigned
## `golf_config` means the built-in one, not the absence of one.
func global_golf_config() -> GolfConfig:
	if _golf_config == null:
		_golf_config = _build_golf_config()
	return _golf_config


## The par system as it applies to ONE island -- the global config narrowed to
## that island's lattice cell, built on first use and cached on it exactly as its
## zones are. This is the "golf config per island" the rest of the game reads:
## hand it a hole index and a length and it answers without a cell in sight.
func golf_config_for(isl: Island) -> GolfConfig:
	if isl == null:
		return global_golf_config()
	if isl.golf == null:
		isl.golf = global_golf_config().for_island(isl.cell)
	return isl.golf


## An island's course total -- the number at the bottom of the scorecard. 0 for
## an island that carries no golf, which is the same answer as "a course of no
## holes" and is the right one: there is nothing to play and nothing to beat.
func course_par(isl: Island) -> int:
	var total := 0
	for entry in holes_for(isl):
		var h: Hole = entry
		total += h.par
	return total


## The course total for the island holding the nearest hole to a logical XZ
## point, or 0 if no hole is within `radius`. The companion to `nearest_hole`:
## one asks what you can play, this asks what the round is worth.
func course_par_near(x: float, z: float, radius := 2000.0) -> int:
	var h := nearest_hole(x, z, radius)
	if h == null:
		return 0
	return course_par(island_for_cell(h.cell))


# The config the field uses when none is assigned. Built rather than kept as a
# default export value so the two thresholds that used to BE the par system stay
# the thing you edit in an `ISLANDFIELD_*.tres`, and so a `.tres` written before
# any of this existed still produces the pars it always did.
func _build_golf_config() -> GolfConfig:
	if golf_config != null:
		return golf_config
	var c := GolfConfig.new()
	c.par3_max = par3_max
	c.par4_max = par4_max
	return c


## Zones whose influence — capsule, wobble and apron — can reach an XZ rect.
##
## This is the reason zones cost almost nothing to render. The mesher calls it
## ONCE per chunk and then loops the survivors per grid point; a 128 m chunk
## overlaps nought to two zones out of the twenty-odd on the hub, so the inner
## loop is nearly always empty or a single capsule.
func zones_in_rect(isl: Island, min_x: float, min_z: float,
		max_x: float, max_z: float) -> Array:
	var all := zones_for(isl)
	var out: Array = []
	for entry in all:
		var zn: Zone = entry
		var reach := zn.width * (1.0 + zone_irregularity) + zn.apron + zn.skirt
		# The ELBOW is part of the bound, not just the two ends. A dogleg's corner
		# sits outside the box its endpoints span, so testing only a and b would
		# drop the zone for exactly the chunks the corner lands in — and a dropped
		# zone is not a missing fairway, it is a fairway with an un-flattened hole
		# punched through the middle of it.
		var lo_x: float = minf(zn.a.x, zn.b.x)
		var hi_x: float = maxf(zn.a.x, zn.b.x)
		var lo_z: float = minf(zn.a.y, zn.b.y)
		var hi_z: float = maxf(zn.a.y, zn.b.y)
		if zn.bent:
			lo_x = minf(lo_x, zn.m.x)
			hi_x = maxf(hi_x, zn.m.x)
			lo_z = minf(lo_z, zn.m.y)
			hi_z = maxf(hi_z, zn.m.y)
		if hi_x + reach < min_x or lo_x - reach > max_x:
			continue
		if hi_z + reach < min_z or lo_z - reach > max_z:
			continue
		out.append(zn)
	return out


## Signed distance in metres from a point to one zone's WOBBLED boundary —
## negative inside, positive out. This is the quantity `zone_at` classifies on,
## and having it separately is what lets a test or a probe say "sample the ground
## 12 m outside this fairway" and mean it, rather than approximating with the
## un-wobbled capsule and smearing every band by a quarter of the hole's width.
##
## NOT what `zone_at` calls per zone: it shares one noise fetch across all of
## them, because the wobble is a property of the ground rather than of any one
## zone. This is the single-zone form, for the callers that have one in hand.
func zone_signed_distance(zn: Zone, x: float, z: float) -> float:
	if not _ready:
		prepare()
	var wob := 1.0 + _zone_noise.get_noise_2d(x, z) * zone_irregularity
	return zn.axis_distance(Vector2(x, z)) - zn.width * wob


## Zone weight in 0..1 at a point: 1 inside a zone's core, falling to 0 over
## `zone_apron` metres outside its wobbled boundary.
##
## TWO WEIGHTS COME OUT OF THIS, and which one a caller wants depends on whether
## it is asking about the LAND or about the COURSE:
##
##   * the RETURN VALUE is the course's: how groomed the ground is. The mown
##     stripe, the bunkers, the woods, "which hole am I on" and "can I build
##     here" all read this, and it falls off from the wobbled boundary exactly as
##     it always did.
##   * `out[4]`, when `out` is sized 5, is the land's: how FLAT the ground is,
##     which is the same ramp with its origin pushed `Zone.skirt` metres further
##     out. Only `base_height` reads it. See `zone_skirt`.
##
## They are equal wherever `skirt` is zero, which is every zone but a golf hole.
## A caller passing a shorter `out` and using the return value for height gets
## the un-skirted shape -- correct-looking but 16 m narrower than the mesher's,
## which is a seam between the ground you see and the ground you stand on. That
## is what `test_island_world`'s "the skirt is the same land everywhere" check
## exists to catch.
##
## `out` receives the DOMINANT zone's details — the one supplying the returned
## weight — so sand and splat agree about which zone the ground belongs to even
## where two aprons overlap. Sized 2 it gets [kind, lift]; sized 3 it also gets
## [index]; sized 4 it also gets [end_dist], the distance in metres to the nearer
## CAP of that zone's axis, which for a golf hole is exactly the distance to the
## tee or the pin and is what `sand_at` keeps bunkers clear of; sized 5 it also
## gets [flatten] as above. `lift` pairs with the FLATTEN weight rather than the
## grooming one, because height is the only thing that reads either of them.
##
## Passing a pre-sized array rather than returning a Dictionary is deliberate:
## this runs per grid vertex, and a Dictionary allocation per vertex is the
## difference between a 35 ms chunk and a 300 ms one.
func zone_at(x: float, z: float, zones: Array, out: Array = []) -> float:
	var kind := ZONE_ROUGH
	var lift := 0.0
	var index := 0
	var end_dist := 1e9
	var best := 0.0
	var best_flat := 0.0
	var want_end := out.size() >= 4
	if not zones.is_empty():
		var p := Vector2(x, z)
		# One noise fetch shared by every zone: the wobble is a property of the
		# GROUND, not of any one zone, so neighbouring boundaries stay consistent
		# and the cost does not scale with the zone count.
		var wob := 1.0 + _zone_noise.get_noise_2d(x, z) * zone_irregularity
		for entry in zones:
			var zn: Zone = entry
			# Signed distance to the wobbled boundary: negative inside.
			var sd := zn.axis_distance(p) - zn.width * wob
			# The apron is the ZONE's, not a global: a 4 m path banks out over 11 m
			# and a 40 m fairway over 75, and one shared number cannot serve both.
			var apron := maxf(zn.apron, 0.001)
			if sd >= apron + zn.skirt:
				continue
			var w := 1.0 - smoothstep(0.0, apron, sd)
			# The skirt is that same ramp with its origin moved out, NOT a wider
			# apron: the bank keeps the slope it was tuned to, it just starts
			# further from the hole. `smoothstep` clamps, so the collar comes out
			# at a flat 1.0 without a second branch.
			var wf := w if zn.skirt <= 0.0 \
					else 1.0 - smoothstep(0.0, apron, sd - zn.skirt)
			if wf > best_flat:
				best_flat = wf
				# Level for everything but a path, where it ramps along the axis --
				# evaluated only for the zone that actually wins, so the graded
				# case costs nothing to the twenty flat ones it is competing with.
				lift = zn.lift_at(p)
			if w > best:
				best = w
				kind = zn.kind
				index = zn.index
				# a square town's cross streets are paved as roads
				if zn.square and zn.on_street(p):
					kind = ZONE_PATH
				if want_end:
					end_dist = minf(p.distance_to(zn.a), p.distance_to(zn.b))
	if out.size() >= 2:
		out[0] = kind
		out[1] = lift
	if out.size() >= 3:
		out[2] = index
	if want_end:
		out[3] = end_dist
	if out.size() >= 5:
		out[4] = best_flat
	return best


# ------------------------------------------------------------------- terrain

# Land height BEFORE sand traps are cut in. Sand needs the local slope, and slope
# comes from this surface, so the two have to be evaluated in that order.
#
# Everything is multiplied by a shore ramp that is 0 at the coastline, so the
# plateau edge always meets the cliff top at exactly the island's `base_y` and
# there is no step to hide.
#
# ZONES ARE APPLIED HERE, by interpolating the whole relief expression toward a
# flat shelf rather than by scaling relief down. The difference matters: scaling
# relief would leave a zone flat only in the sense of "less bumpy", still
# inheriting whatever slope the hill field had across it, so a fairway laid over
# a hillside would come out as a smooth ramp. Replacing relief with a constant
# makes the zone genuinely level, and the apron carries the hills back up around
# its rim.
#
# `zone_flat` is the FLATTEN weight -- `zone_at`'s `out[4]`, not its return value.
# This is the only function in the file that wants that one; see `zone_skirt`.
func base_height(x: float, z: float, mask: float, owner: Island,
		zone_flat := 0.0, zone_lift := 0.0) -> float:
	if owner == null:
		return 0.0
	var t := clampf(mask / maxf(shore_width, 0.001), 0.0, 1.0)
	var shore := t * t * (3.0 - 2.0 * t)
	# SPARSIFIED HILLS. The raw fBm is remapped to 0..1 and then clipped from
	# below, so everything under `hill_sparsity` is dead flat at the island's base
	# altitude and only the top of the distribution rises. That inverts the
	# composition: instead of a uniform swell with no level ground anywhere, most
	# of the wild ground is flat and the whole of `hill_height` is spent on the
	# few places that are not. It is also the reason the hills can be this tall
	# without the island turning into a ridge field.
	var hills := smoothstep(hill_sparsity, minf(hill_sparsity + hill_ramp, 1.0),
			_hill_noise.get_noise_2d(x, z) * 0.5 + 0.5)
	# FRACTAL_RIDGED already returns spine-shaped noise; remap to 0..1 so ridges
	# only ever add height rather than carving below the shore line. Masked by the
	# hill shape so spines are the crests of hills rather than a carpet that would
	# quietly fill in every flat `hill_sparsity` just made.
	var ridges := (_ridge_noise.get_noise_2d(x, z) * 0.5 + 0.5) \
			* lerpf(1.0, hills, ridge_on_hills)
	var micro := _micro_noise.get_noise_2d(x, z)
	var relief := hill_height * hills + ridge_height * ridges
	var ground := owner.peak * relief + micro_height * micro
	var f := clampf(zone_flat, 0.0, 1.0)
	if f > 0.0:
		# The shelf keeps a long, shallow contour so a putt has something to
		# break on, and a fraction of the micro detail so groomed ground still
		# has a texture underfoot.
		var shelf := zone_lift \
				+ green_undulation * _green_noise.get_noise_2d(x, z) \
				+ micro_height * micro * green_micro
		ground = lerpf(ground, shelf, f)
	return owner.base_y + shore * ground


# Sand-trap weight in 0..1 at a point, given the local slope of the base surface
# (0 = flat, 1 = vertical) and the landmass mask.
#
# A TRAP IS A DISC AROUND A POINT, not a level set of a noise field, and the
# difference is the whole design. Thresholding smooth noise cannot produce traps
# of consistent size, because the size of a level set is not something the
# threshold controls: the field has broad high plateaux in some places and
# barely crests the line in others, so one blob sprawls and the next is a speck.
# Measured on the version this replaced: nine traps spanning 208 to 6512 m2, a
# 31-fold spread, off a single threshold. No amount of coverage or contrast
# tuning narrows that -- contrast sharpens the EDGE, it does not make the lobes
# the same size, and every pass that tried to fix the spread from those two
# dials moved the count instead.
#
# Distance to the nearest point of a jittered grid inverts the problem. Size is
# a radius, count is a spacing, and evenness is a property of the grid rather
# than a hope about the noise. The organic outline that the noise threshold was
# there to provide comes back as a wobble on the radius, which perturbs the
# shape without touching the area much.
func sand_at(x: float, z: float, mask: float, slope: float,
		zone_flat := 0.0, zone_kind := ZONE_ROUGH, end_dist := 1e9) -> float:
	if not sand_enabled:
		return 0.0
	var d := sand_distance(x, z)
	# Ground beyond the widest the edge could possibly reach is just ground.
	# Worth an early return: most of the fairway is nowhere near a bunker, and
	# this is called per vertex plus four more times per vertex for the
	# sand-aware shading normal, so it keeps the wobble fetch and every rule
	# below off the common case.
	if d >= sand_radius + sand_wobble + sand_edge_m:
		return 0.0
	if sand_wobble > 0.0:
		d += sand_wobble * _sand_wobble_noise.get_noise_2d(x, z)
	# Reversed edges, which Godot's smoothstep handles (GLSL's would not): 1
	# inside the trap, falling to 0 across `sand_edge_m` at the rim.
	var s := smoothstep(sand_radius, sand_radius - sand_edge_m, d)
	if s <= 0.0:
		return 0.0
	# Flat ground only, and never straddling the cliff edge.
	s *= 1.0 - smoothstep(sand_max_slope * 0.6, sand_max_slope, slope)
	s *= smoothstep(0.0, maxf(sand_coast_margin, 0.001), mask)
	# A bunker is part of a hole, so sand is gated on zone membership rather than
	# scattered over every flat patch in the world. Note this is the third and
	# smallest of the nested boundaries: island coastline, then zone edge, then
	# the traps inside it.
	var f := clampf(zone_flat, 0.0, 1.0)
	if zone_kind == ZONE_GOLF:
		# ...and never on the teeing ground or the pin. Both are capsule ends, so
		# `end_dist` from `zone_at` is exactly the distance to whichever is nearer.
		if sand_end_clear > 0.0:
			s *= smoothstep(0.0, sand_end_clear, end_dist)
		return s * lerpf(sand_rough_gain, 1.0, f)
	if zone_kind == ZONE_BUILD or zone_kind == ZONE_PATH:
		# No sand on a build pad or a track: a foundation wants ground, a path
		# wants to be walkable, and a pad the player cannot use is worse than no
		# pad. Both fade to zero over their bank rather than snapping.
		return s * lerpf(sand_rough_gain, 0.0, f)
	return s * sand_rough_gain


## Metres from a point to the centre of the nearest sand trap, ignoring every
## rule about whether a trap is actually allowed there.
##
## FastNoiseLite's cellular RETURN_DISTANCE is a true Euclidean distance field
## measured in cells and biased by -1, so this conversion is exact rather than
## fitted -- see `prepare()` for the check. Public because `SCRIPT_measure_sand.gd`
## locates trap centres by finding this field's minima, and a second copy of the
## conversion there could drift out of step with this one.
func sand_distance(x: float, z: float) -> float:
	return (_sand_noise.get_noise_2d(x, z) + 1.0) * sand_spacing


## The centre of the trap nearest a point, to sub-metre accuracy.
##
## Exact in ONE step, and that is a property of the field rather than a lucky
## iteration count: `sand_distance` is a true Euclidean distance field, so its
## gradient is the unit vector pointing directly away from the nearest centre,
## and walking back down it by exactly the distance arrives. Hunting for local
## minima on a raster instead -- the obvious approach -- localises a centre only
## to the raster pitch, which is several metres of error in a check whose whole
## job is to compare separations against a trap width.
##
## Only meaningful within about half a cell of a centre. Further out the nearest
## centre changes across the cell boundary and the gradient points at a
## different trap; callers raster at well under `sand_spacing` and keep the
## points that come back close.
func trap_centre_near(x: float, z: float) -> Vector2:
	var d := sand_distance(x, z)
	var e := 0.5
	var gx := (sand_distance(x + e, z) - sand_distance(x - e, z)) / (2.0 * e)
	var gz := (sand_distance(x, z + e) - sand_distance(x, z - e)) / (2.0 * e)
	var g := Vector2(gx, gz)
	if g.length_squared() < 1e-6:
		return Vector2(x, z)
	return Vector2(x, z) - g.normalized() * d


## Every trap centre within `radius` metres of a point, to sub-metre accuracy
## and each reported once.
##
## Three steps, and each of the last two exists because the naive version was
## measurably wrong:
##
## 1. Raster a net fine enough that every centre catches a sample.
## 2. Refine each hit with `trap_centre_near`, then CHECK IT LANDED. A sample
##    that straddles a cell boundary refines toward a neighbour's centre and
##    arrives nowhere in particular; a real centre is where the distance field
##    reads zero, so anything else is discarded.
## 3. Cluster, because dozens of samples resolve to the same trap and the
##    finite-difference gradient scatters their answers over a metre or so.
##    Rounding to a grid instead of clustering splits one trap into two whenever
##    that scatter straddles a boundary -- which reported a pair of centres 1.0 m
##    apart, read as two traps merging, and nearly cost a good jitter value.
func trap_centres_in_disc(centre: Vector2, radius: float) -> Array[Vector2]:
	var out: Array[Vector2] = []
	if not sand_enabled:
		return out
	var step := clampf(sand_spacing * 0.12, 2.0, 20.0)
	# Buckets a good deal wider than the cluster radius, so a 3x3 neighbourhood
	# is guaranteed to contain every centre that could be the same trap.
	var bucket := 12.0
	var index := {}
	var n := int(radius * 2.0 / step) + 2
	for iy in n:
		for ix in n:
			var x := centre.x + (float(ix) - float(n) * 0.5) * step
			var z := centre.y + (float(iy) - float(n) * 0.5) * step
			if Vector2(x, z).distance_to(centre) > radius:
				continue
			# A sample this close to a centre is well inside its cell, so the
			# gradient there points at that centre and nothing else.
			if sand_distance(x, z) > step:
				continue
			var c := trap_centre_near(x, z)
			if sand_distance(c.x, c.y) > 0.5:
				continue
			var key := Vector2i(floori(c.x / bucket), floori(c.y / bucket))
			var seen := false
			for oz in range(-1, 2):
				for ox in range(-1, 2):
					var q := key + Vector2i(ox, oz)
					if not index.has(q):
						continue
					for p in index[q]:
						if (p as Vector2).distance_squared_to(c) < 25.0:
							seen = true
							break
					if seen:
						break
				if seen:
					break
			if seen:
				continue
			if not index.has(key):
				index[key] = []
			index[key].append(c)
			out.append(c)
	return out


## Is a bunker even possible at a point, given its zone membership? Cheap enough
## to gate the four extra noise fetches the sand-aware shading normal costs — see
## `SCRIPT_chunk_mesher.gd` — without evaluating the trap mask itself.
func sand_possible(zone_flat: float, zone_kind: int) -> bool:
	if not sand_enabled:
		return false
	if sand_rough_gain > 0.0:
		return true
	return zone_kind == ZONE_GOLF and zone_flat > 0.0


# ------------------------------------------------------------------ crater

## The crash site on an island, built on first use and cached on it. Null for an
## island that carries none — which is most of them.
##
## Threading note: identical to `zones_for`, and safe for the same reason. This
## mutates the `Island`, but every worker holds its own `clone()` and the
## placement is seeded from the island's cell and `world_seed` alone, so every
## thread independently derives the same crater rather than sharing one.
func crater_for(isl: Island) -> Crater:
	if isl == null:
		return null
	if not _ready:
		prepare()
	if not isl.crater_built:
		isl.crater = _place_crater(isl)
		isl.crater_built = true
	return isl.crater


## How BURNT the ground looks, from `crater_at`'s radial weight.
##
## The two are different questions off one channel and this is the difference.
## `crater_at().y` is a radial coordinate — 1 on the floor, `crater_rim_paint` at
## the crest, 0 out past the ash — and the classification rules read it as one,
## placing themselves at levels along it. Nothing about the LOOK of burnt ground
## is linear in that: the lip crest is not half-charred because it happens to sit
## halfway out, it is charred outright, and it is the outer apron that fades.
##
## So: saturated well inside the crest, and the whole fade spent on the ash. What
## the splat lerps by and what the shader mixes by are both this, never the raw
## weight — and the mesher writes THIS into the vertex channel, so the shader is
## handed the answer rather than the coordinate and needs no copy of
## `crater_char_full` to re-derive it.
func crater_burn(crater_weight: float) -> float:
	return smoothstep(0.0, maxf(crater_char_full, 0.001), clampf(crater_weight, 0.0, 1.0))


## Is a point within reach of the crash site, allowing `pad` metres of slack?
##
## Cheap enough to gate the extra work a crater-aware shading normal costs in
## `SCRIPT_chunk_mesher.gd` — one squared-distance compare against the long axis —
## without evaluating the crater itself. Conservative on every bearing, since
## `outer` is measured along the LONGEST one.
func crater_near(x: float, z: float, crater: Crater, pad := 0.0) -> bool:
	if crater == null:
		return false
	var r := crater.outer + maxf(pad, 0.0)
	return crater.center.distance_squared_to(Vector2(x, z)) < r * r


## The crater at a point. Returns BOTH products of one radial evaluation, packed:
##
##   x — the height offset in METRES. Negative through the bowl, positive on the
##       lip, zero everywhere else. Goes into `surface_height`.
##   y — the RADIAL WEIGHT in 0..1: 1 on the fused floor, `crater_rim_paint` at
##       the lip crest, 0 past the ash. Goes to `splat_weights` raw, because the
##       rules there are levels on this curve; the mesher writes `crater_burn` of
##       it into the vertex channel instead, because what a shader wants is how
##       burnt the ground looks rather than where in the crater it is.
##   z — the MOLTEN CORE in 0..1: 1 at the impact point, 0 by `crater_molten` of
##       the radius and everywhere outside it. The shader opens the slag's crack
##       network into a pool with it.
##
## z EXISTS BECAUSE y IS FLAT WHERE IT IS NEEDED. Inside `crater_floor_frac` the
## paint weight is exactly 1.0 — that is what a flat floor means — so it carries
## no information at all across the one part of the crater the molten term is
## about. Deriving the pool from `t` directly is the only honest way to get it,
## and doing that here rather than in a second function keeps it on the same
## early-out and the same wobble fetch as the other two.
##
## ONE function rather than two because the expensive half — the impact-frame
## transform and the wobble fetch — is shared, and because two functions could
## drift: a hole in one place and a burn in another is the exact failure the
## single `forest_at` mask exists to prevent for woods.
##
## The weight is MONOTONE in the radial coordinate by construction, and that is
## what lets one channel carry the whole radial story downstream. High is floor,
## mid is wall, `crater_rim_paint` is the crest, low is ash drifting out into the
## grass — so every consumer can place itself in the crater from a single float
## without being told where the centre is.
func crater_at(x: float, z: float, mask: float, crater: Crater,
		base_h := INF) -> Vector3:
	if crater == null:
		return Vector3.ZERO
	var p := Vector2(x, z) - crater.center
	# Early out on the long-axis radius, squared so the common case costs no
	# sqrt. Most of an island is nowhere near the crash site, and this runs per
	# vertex plus four more times per vertex for the shading normal.
	if p.length_squared() >= crater.outer * crater.outer:
		return Vector3.ZERO

	# Into the impact frame: `u` runs along the ship's travel, `v` across it.
	var h := crater.heading
	var u := p.x * h.x + p.y * h.y
	var v := -p.x * h.y + p.y * h.x
	var e := maxf(crater_elongation, 1.0)
	var r := maxf(crater.radius, 0.001)
	# Dividing the ALONG component is what stretches the footprint down the
	# approach. Note it leaves `t` reading 1 at the rim on every bearing, so every
	# rule below stays written in rim-relative units and none of them has to know
	# the crater is an ellipse at all.
	var uu := u / e
	var d := sqrt(uu * uu + v * v)
	if crater_wobble > 0.0:
		d += crater_wobble * _crater_wobble_noise.get_noise_2d(x, z)
	var t := d / r
	# Where along the approach this is: -1 at the entry end, +1 at the far wall.
	var along := clampf(u / (r * e), -1.0, 1.0)

	# THE BOWL: 1 across the flat floor, easing to 0 at the rim. The floor is
	# flat rather than a paraboloid run to a point because the substrate melted
	# and pooled — and because a funnel gives the ship nowhere to sit.
	var floor_t := clampf(crater_floor_frac, 0.0, 0.9)
	var bowl := 1.0 - smoothstep(floor_t, 1.0, t)
	# The entry end is a ramp: the ship came in low and dug in progressively, so
	# the ground rises out of the bowl the way it came.
	#
	# MEASURED FROM THE EDGE OF THE FLOOR, NOT FROM THE MIDDLE OF THE CRATER, and
	# that subtraction is the whole of what makes the floor FLAT. `bowl` is pinned
	# at exactly 1 inside `floor_t` — that is what a flat floor means — but this
	# term multiplies it, and read off the raw `along` it keeps varying across the
	# pad the pin just flattened. Measured on the shipped numbers the floor came
	# out tilted 0.93 m across itself, rising toward the entry: a smooth slope,
	# nothing that reads as a bug from the rim, and enough to stand a 15 m hull
	# nose-up in ground that was supposed to be level. The wreck is what found it.
	#
	# So the ramp starts where the wall does. It reaches exactly the same value at
	# the entry rim as it always did — `1 - crater_entry_ramp` at `along` -1 — so
	# the way out is as shallow as it ever was and only the part of the curve that
	# was lying about the floor has changed. The two halves of the wall keep their
	# asymmetry; the pad between them keeps nothing but its depth.
	var entry := maxf(-along, 0.0)
	var ramp := 1.0 - clampf(crater_entry_ramp, 0.0, 0.95) \
			* maxf(entry - floor_t, 0.0) / maxf(1.0 - floor_t, 0.001)

	# THE LIP: a ridge peaking exactly at the rim, steep on the inside and drawn
	# out on the outside. Two smoothsteps rather than a bump function, because the
	# asymmetry between them is most of what makes a rim read as THROWN — ejecta
	# piled against the hole it came out of — rather than as a moulded ring.
	var lip := smoothstep(1.0 - crater_lip_inner, 1.0, t) \
			* (1.0 - smoothstep(1.0, 1.0 + crater_lip_outer, t))
	# ...and it is piled higher in front of the gouge, because that is where
	# everything the gouge displaced ended up.
	var throw := 1.0 + clampf(crater_far_throw, 0.0, 1.0) * along

	var lift := crater_rim * lip * throw - crater_depth * bowl * ramp

	# AND THE FLOOR IS PINNED TO A DATUM, which is what makes it FLAT rather than
	# merely level with itself. Everything above is a height OFFSET, and `bowl` is
	# exactly 1 inside `crater_floor_frac`, so the offset across the floor is a
	# constant `-crater_depth`. The ground it is added to is not constant: the crash
	# site sits in wild forest and the island's hills keep rising underneath it, so a
	# floor with a perfectly flat lift fell 0.86 m across itself on the shipped seed.
	# Nothing in a bowl reads that as a slope — but the wreck lies ON it, and a ship
	# standing on a plane that is a metre out is a ship with a corner in the air.
	#
	# `bowl` IS ALREADY THE RIGHT CURVE and is reused rather than measured again: 1
	# across the floor, easing to 0 at the rim on the same smoothstep the depth uses.
	# So the correction is total where the floor is and has died out entirely by the
	# lip, which is what keeps this from being a disc of levelled ground with an edge.
	#
	# The default of INF is what a caller that has no base height to offer passes;
	# it makes the term exactly zero rather than pinning the floor to a datum the
	# caller never supplied. `crater_flat_floor` off restores the constant-offset
	# behaviour for an A/B.
	if crater_flat_floor and bowl > 0.0 and base_h < INF:
		lift += (crater.floor_base_y - base_h) * bowl

	# THE PAINT, in two pieces. Inside the rim it tracks depth; outside it, the
	# ash drifts out to nothing. One smoothstep across the whole span instead is
	# dominated by `crater_ash_reach` — measured on the shipped numbers the wall
	# sits at 0.97 against the floor's 1.00, and `crater_fuse_weight` could not
	# tell the two apart. The pieces meet at `crater_rim_paint` by construction,
	# so the curve is continuous and stays monotone.
	var rim_p := clampf(crater_rim_paint, 0.05, 1.0)
	var paint: float
	if t <= 1.0:
		paint = 1.0 - (1.0 - rim_p) * smoothstep(floor_t, 1.0, t)
	else:
		paint = rim_p * (1.0 - smoothstep(1.0, 1.0 + crater_ash_reach, t))

	# NEVER STRADDLE THE CLIFF EDGE. `_place_crater` already keeps the whole
	# footprint inland, so this is the belt to that braces — but it is one
	# smoothstep, and a bowl cut through the coastline contour is the single
	# failure here that tears the mesh rather than merely looking wrong: the
	# cliff sweep hangs off the contour, and a hole in the contour is a hole in
	# the cliff.
	var coast := smoothstep(0.0, maxf(crater_coast_margin, 0.001), mask)

	# THE MOLTEN POOL, straight off the radial coordinate rather than off the
	# paint. Measured in the WOBBLED frame like everything else here, so the pool
	# is the same shape as the floor it lies in — a circular pool in a lobed bowl
	# would be the one part of the crater that looked machined.
	var molten := 0.0
	if crater_molten > 0.0:
		molten = 1.0 - smoothstep(0.0, crater_molten, t)
	return Vector3(lift * coast, clampf(paint, 0.0, 1.0) * coast, molten * coast)


## The crash site's EXCAVATED radius: the rim on the long axis, wobble included.
##
## This is the one the coastline rules are written against, and the distinction
## from `crater_outer_radius` below is the whole of why they work. What can tear
## the mesh is DIGGING near the contour — the cliff sweep hangs off the coastline,
## so a bowl cut through it is a hole in the cliff. Ash blowing out to the shore
## is not that. It is not even a problem: a burn that runs to the cliff edge is
## what a burn does, and `crater_at` fades it out over `crater_coast_margin`
## anyway.
##
## Holding the PAINT to the digging rule was the first version and it cost the
## feature outright. Measured at the crater size of the day, `crater_outer_radius`
## was 176 m against this 95 m, which on the shipped hub demanded a centre at mask
## 0.191 — and at that inset, on all 24 bearings, the best ring clearance the
## island had to offer was 0.0487 against a 0.05 margin. Every bearing was
## rejected and the hub carried no crash site at all. The crater is half that size
## now (48 m of excavation against 70 m of paint) and the two radii no longer
## strain the island, which is exactly when a rule like this stops being visible
## and starts being load-bearing.
func crater_bowl_radius() -> float:
	return crater_radius * maxf(crater_elongation, 1.0) + crater_wobble


## Radius past which the crash site moves and paints nothing, in metres, measured
## along its LONG axis — so one distance test against this is conservative on
## every bearing. This is the early-out `crater_at` and `crater_near` use, and
## `Crater.outer` is a copy of it. NOT a placement rule; see above.
func crater_outer_radius() -> float:
	return crater_bowl_radius() * (1.0 + maxf(crater_ash_reach, crater_lip_outer))


## The mask level `_place_crater` actually solves for on an island — which is
## `crater_shore_mask`, RAISED wherever the excavation would not fit inside it.
##
## The mask falls as `1 - d / radius`, so a bowl `crater_bowl_radius()` metres
## across costs `bowl / radius` of mask on its seaward side. A centre any closer
## in than that plus `crater_coast_margin` hangs the bowl over the cliff on every
## bearing, not just an unlucky one.
##
## On the shipped hub that is 95 / 1250 + 0.05 = 0.126, well under the 0.30
## requested, so the export governs and the derivation is the floor under it.
## It stops being inert on a smaller island or under a bigger crater — which is
## exactly where a hand-tuned request goes quietly wrong, in the way that tears
## the cliff. At `crater_min_radius`, the smallest island that carries one at
## all, it is 95 / 300 + 0.05 = 0.367 and it is the DERIVATION that governs: on a
## 300 m island a crater this size has to sit further in than the request asks,
## and the request never gets a say.
##
## Public because `tests/TEST_island_world.gd` checks placement against it, and a
## second copy of this arithmetic in the test would only prove the copy agrees
## with itself.
func crater_shore_target(isl: Island) -> float:
	return maxf(crater_shore_mask,
			crater_coast_margin + crater_bowl_radius() / maxf(isl.radius, 1.0))


# ------------------------------------------------------------- the pod's divot

## The escape pod's dent, built on first ask and cached on the island.
##
## GATED ON THE CRATER by asking for it: no crash site, no pod. `crater_for` is
## safe to call from here because the dependency runs one way only — the crater's
## placement never asks for a divot back — which is the same rule that lets
## `_place_crater` ask for the zones.
func divot_for(isl: Island) -> Divot:
	if isl == null:
		return null
	if not _ready:
		prepare()
	if not isl.divot_built:
		isl.divot = _place_divot(isl)
		isl.divot_built = true
	return isl.divot


## How TORN the ground looks, from `divot_at`'s radial weight — the counterpart
## of `crater_burn`, and the same argument for existing.
##
## The radial weight is a coordinate: 1 on the floor, `divot_rim_paint` at the
## crest, 0 out past the scuff. Nothing about the LOOK of disturbed ground is
## linear in that, so the remap saturates well inside the rim and spends the whole
## fade on the outermost scuff. The mesher writes THIS into the vertex channel,
## so the shader is handed the answer rather than the coordinate.
func divot_scuff(divot_weight: float) -> float:
	return smoothstep(0.0, maxf(divot_scuff_full, 0.001), clampf(divot_weight, 0.0, 1.0))


## Is a point within reach of the pod's dent, allowing `pad` metres of slack?
##
## Same shape and same job as `crater_near`: one squared-distance compare against
## the long axis, conservative on every bearing, cheap enough to gate the extra
## work a divot-aware shading normal costs without evaluating the divot itself.
func divot_near(x: float, z: float, divot: Divot, pad := 0.0) -> bool:
	if divot == null:
		return false
	var r := divot.outer + maxf(pad, 0.0)
	return divot.center.distance_squared_to(Vector2(x, z)) < r * r


## The divot at a point, packed the way `crater_at` is:
##
##   x — the height offset in METRES. Negative through the trough, positive on
##       the bank, zero everywhere else. Goes into `surface_height`.
##   y — the RADIAL WEIGHT in 0..1: 1 on the floor, `divot_rim_paint` at the bank
##       crest, 0 past the scuff. Goes to `splat_weights` raw, because the rules
##       there are levels on this curve; the mesher writes `divot_scuff` of it
##       into the vertex channel instead.
##
## TWO CHANNELS, NOT THREE. The crater's third is its molten core, and there is
## nothing here that a radial coordinate cannot say — the dent has no hot middle,
## and `z` is left at zero rather than given a meaning nobody asks for. Returning
## a Vector3 anyway keeps the two features' signatures the same shape, which is
## what lets the mesher treat them as one kind of thing.
##
## THE ASYMMETRY LIVES IN `along`, and it is worth being explicit that this is
## the only structural difference from `crater_at`. There, the lip is a full ring
## and `crater_far_throw` merely piles it higher at one end. Here the lip is
## MULTIPLIED BY the far half — `max(along, 0)` to a power — so it does not exist
## at the entry end at all. That is what makes the dent a comma rather than a
## small crater, and it is what the pod leans on.
func divot_at(x: float, z: float, mask: float, divot: Divot,
		base_h := INF) -> Vector3:
	if divot == null:
		return Vector3.ZERO
	var p := Vector2(x, z) - divot.center
	# Early out on the long-axis radius, squared so the common case costs no
	# sqrt. Runs per vertex plus four more times per vertex for the shading
	# normal, on a dent that is 20 m across on a 2.5 km island.
	if p.length_squared() >= divot.outer * divot.outer:
		return Vector3.ZERO

	# Into the impact frame: `u` runs along the pod's travel, `v` across it.
	var h := divot.heading
	var u := p.x * h.x + p.y * h.y
	var v := -p.x * h.y + p.y * h.x
	var e := maxf(divot_elongation, 1.0)
	var r := maxf(divot.radius, 0.001)
	var uu := u / e
	var d := sqrt(uu * uu + v * v)
	if divot_wobble > 0.0:
		d += divot_wobble * _divot_wobble_noise.get_noise_2d(x, z)
	var t := d / r
	# Where along the skid this is: -1 at the open entry, +1 at the bank.
	var along := clampf(u / (r * e), -1.0, 1.0)

	# THE TROUGH: 1 across the flat floor, easing to 0 at the rim.
	var floor_t := clampf(divot_floor_frac, 0.0, 0.9)
	var bowl := 1.0 - smoothstep(floor_t, 1.0, t)
	# The entry end is open: the pod came in shallow and dug in progressively, so
	# the ground rises out of the trough the way it came. Measured from the EDGE
	# of the floor rather than from the middle of the dent, which is what keeps
	# the floor flat — see `crater_at`'s `ramp`, which is the same construction
	# and carries the full derivation.
	var entry := maxf(-along, 0.0)
	var skid := 1.0 - clampf(divot_entry_open, 0.0, 1.0) \
			* maxf(entry - floor_t, 0.0) / maxf(1.0 - floor_t, 0.001)

	# THE BANK, and it is only at the far end. Same two-smoothstep ridge the
	# crater's lip is — steep inside, drawn out beyond — gated on the far half so
	# there is no rim behind the pod at all.
	var ridge := smoothstep(1.0 - divot_bank_inner, 1.0, t) \
			* (1.0 - smoothstep(1.0, 1.0 + divot_bank_outer, t))
	var front := pow(maxf(along, 0.0), maxf(divot_bank_focus, 0.5))

	var lift := divot_bank * ridge * front - divot_depth * bowl * skid

	# AND THE FLOOR IS PINNED TO A DATUM, for the reason `Divot.floor_base_y`
	# gives: not because the pod would notice 0.1 m of fall across 7 m, but
	# because the bank's height is measured from the floor and the pod's lean is
	# measured from the bank. `bowl` is already the right curve — 1 across the
	# floor, dead by the rim — so the correction never reaches the bank it is
	# protecting the height of.
	if bowl > 0.0 and base_h < INF:
		lift += (divot.floor_base_y - base_h) * bowl

	# THE PAINT, in the same two pieces `crater_at` uses and meeting at
	# `divot_rim_paint` by construction, so the curve is continuous and monotone.
	var rim_p := clampf(divot_rim_paint, 0.05, 1.0)
	var paint: float
	if t <= 1.0:
		paint = 1.0 - (1.0 - rim_p) * smoothstep(floor_t, 1.0, t)
	else:
		paint = rim_p * (1.0 - smoothstep(1.0, 1.0 + divot_scuff_reach, t))

	# NEVER STRADDLE THE CLIFF EDGE. `_place_divot` already keeps the whole
	# footprint inland; this is the belt that braces, and it is the same one
	# `crater_at` wears for the same reason — a hole in the coastline contour is
	# a hole in the cliff sweep that hangs off it.
	var coast := smoothstep(0.0, maxf(divot_coast_margin, 0.001), mask)

	return Vector3(lift * coast, clampf(paint, 0.0, 1.0) * coast, 0.0)


## The divot's EXCAVATED radius: the rim on the long axis, wobble included. The
## coastline rules are written against this rather than against the painted
## radius, for the reason `crater_bowl_radius` records — digging near the contour
## is what tears the mesh, and scuffed dirt reaching the shore is not even a
## problem.
func divot_bowl_radius() -> float:
	return divot_radius * maxf(divot_elongation, 1.0) + divot_wobble


## Radius past which the divot moves and paints nothing, along its LONG axis.
## `Divot.outer` is a copy of it, and it is what both early-outs test.
func divot_outer_radius() -> float:
	return divot_bowl_radius() * (1.0 + maxf(divot_scuff_reach, divot_bank_outer))


## The mask level `_place_divot` solves for — `divot_shore_mask`, raised wherever
## the trough would not fit inside it. The same derivation as
## `crater_shore_target`, and public for the same reason: the test checks
## placement against it, and a second copy of the arithmetic would only prove the
## copy agrees with itself.
##
## On the shipped hub this is 0.04 + 15 / 1250 = 0.052 against the 0.45 requested,
## so the export governs by a wide margin — a 20 m dent simply does not strain a
## 2.5 km island the way a 90 m crater does.
func divot_shore_target(isl: Island) -> float:
	return maxf(divot_shore_mask,
			divot_coast_margin + divot_bowl_radius() / maxf(isl.radius, 1.0))


# Golden angle. Striding bearings by it visits a circle in an order that is
# already well spread after any number of steps, which a uniform sweep from a
# random start is not — see `_place_crater`.
const CRATER_BEARING_STRIDE := 2.39996322972865332

# How many points a candidate's outer ring is tested at.
#
# HIGH, AND MEASURED RATHER THAN CHOSEN, because the thing being sampled is a
# coastline that is jagged at the crater's own scale. `crater_shore_target` gets
# the centre into the right neighbourhood assuming a circular island; what
# decides whether a particular bearing is actually safe is this check, so it has
# to converge. Measured on the shipped hub at the 176 m ring the crater had when
# this was written — the ring is 48 m now, subtending a fifth of the bearing span
# and so needing far fewer samples, which makes 192 conservative rather than
# merely sufficient. The true worst mask on that ring was 0.0487, and sampling it
# at:
#
#      8 points reports 0.1320   -- wrong by a factor of three, and it passes
#     24 points reports 0.0757
#     64 points reports 0.0517   -- still optimistic, still passes a 0.05 margin
#    256 points reports 0.0489
#   1024 points reports 0.0487
#
# The first two both accepted a site whose footprint genuinely overhung the
# margin. The wobble term varies by 0.235 across one ring, which is what makes a
# coarse sample not merely imprecise but confidently wrong. 192 is inside a
# thousandth of converged and costs 192 noise fetches per candidate bearing,
# once per island, cached on it forever.
const CRATER_RING_SAMPLES := 192

# How many points `crater_forest_score` averages over, as rings x bearings across
# the painted footprint, plus the centre.
#
# MEASURED, AND WHAT HAD TO CONVERGE IS THE WINNING BEARING, NOT THE SCORE. The
# score exists only to rank candidates, so a value off by a tenth costs nothing
# as long as it puts the same site first. That is a lower bar than the coast
# ring's, and it still is not met by a handful of points: `forest_at` is a
# THRESHOLDED noise — a smoothstep 0.06 wide — so what is being averaged flips
# between 0 and 1 across a footprint the underlying 520 m blob barely varies
# over. tests/PROBE_crater_forest_samples.gd walks the ladder on four seeds, at
# the shipped `crater_shore_mask`:
#
#              1 pt    9    17    25    49    193
#     1337      i0*   i0    i21   i21   i21   i21
#        7      i1*   i19   i19   i19   i19   i19
#    90210      i0*   i13   i13   i13   i13   i13
#       11      i3*   i12   i12   i23   i23   i23
#
#   * the centre alone saturates at 1.0 on any site whose middle is wooded, so
#     every candidate ties and the winner is whichever came first — which is the
#     zone-only rule again, with extra steps.
#
# 25 IS THE FIRST RUNG THAT IS RIGHT EVERYWHERE, and it is not one to spare: 9
# picks the wrong bearing on two of the four seeds and 17 still does on seed 11.
# Every rung above it agrees with 25, so this is the knee and not a point on the
# way up. Sampled to the PAINTED radius and no further — carried out to 1.25x it
# answers i12 on seed 11 where the footprint itself says i23, because the extra
# ring is ground the crater never touches and all it does is outvote the ground
# that it does.
const CRATER_FOREST_RINGS := 3
const CRATER_FOREST_BEARINGS := 8


## How WOODED a candidate crash site is, in 0..1 — the mean of `forest_at` over
## the crater's painted footprint.
##
## THE SAME QUESTION THE TREE SCATTER ASKS, argument for argument, and the
## landform slope is passed even though it measured completely inert: on four
## seeds the winning bearing and its score were identical to three decimals with
## the term on and off, because a site solved onto a shore contour has a mean
## slope of 0.003 .. 0.023 and the canopy does not start thinning until
## `forest_max_slope * FOREST_SLOPE_KNEE` = 0.29. Dropping it would be five times
## cheaper and would ask a DIFFERENT question — an upper bound on the forest
## rather than the forest — and `forest_at`'s own note is that two consumers of it
## cannot be allowed to disagree about where the wood is. The way that failure
## would show up here is a crater sited in a wood the scatter then declines to
## plant, which is exactly the bald crash site this scoring was added to fix.
##
## IT CANNOT GO THROUGH `sample()`, which is where every other caller gets its
## slope: `sample` asks for `crater_for`, and this runs to decide what that
## returns. So the landform normal is rebuilt here out of `_zoned_height`, the
## same way `sample` builds it and at the same `curvature_radius` spacing.
##
## Points that fall in the sea are averaged in as ZEROES rather than skipped. A
## footprint hanging half over the water genuinely is half unwooded, and the
## convergence table above was measured this way.
##
## Public because `tests/TEST_island_world.gd` checks the placement against it,
## for the same reason `crater_shore_target` is — a second copy of this in the
## test would only prove the copy agrees with itself.
func crater_forest_score(isl: Island, centre: Vector2, zones: Array = []) -> float:
	if isl == null:
		return 0.0
	if zones.is_empty():
		zones = zones_for(isl)
	var outer := crater_outer_radius()
	var d := maxf(curvature_radius, 0.01)
	var sum := 0.0
	var n := 0
	for ri in range(CRATER_FOREST_RINGS + 1):
		var r := 0.0 if ri == 0 else outer * float(ri) / float(CRATER_FOREST_RINGS)
		var nb := 1 if ri == 0 else CRATER_FOREST_BEARINGS
		for k in range(nb):
			var a := TAU * float(k) / float(nb)
			var p := centre + Vector2(cos(a), sin(a)) * r
			n += 1
			var mask := mask_for(isl, p.x, p.y)
			if mask <= 0.0:
				continue
			var zi: Array = [ZONE_ROUGH, 0.0, 0, 1e9, 0.0]
			zone_at(p.x, p.y, zones, zi)
			var islands := islands_at(p.x, p.y)
			var hx0 := _zoned_height(p.x - d, p.y, islands, isl, zones)
			var hx1 := _zoned_height(p.x + d, p.y, islands, isl, zones)
			var hz0 := _zoned_height(p.x, p.y - d, islands, isl, zones)
			var hz1 := _zoned_height(p.x, p.y + d, islands, isl, zones)
			var nrm := Vector3((hx0 - hx1) / (2.0 * d), 1.0,
					(hz0 - hz1) / (2.0 * d)).normalized()
			sum += forest_at(p.x, p.y, mask, clampf(1.0 - nrm.y, 0.0, 1.0), zi[4])
	return sum / maxf(float(n), 1.0)


# Put the crash site inland of the shore, clear of the course, and in a wood.
#
# THE SEARCH IS OVER BEARINGS, not over the disc, and that is what makes it both
# cheap and exact. Solving for a mask level fixes one of the two degrees of
# freedom outright — the site is somewhere on the contour where the mask reads
# `crater_shore_mask` — so what is left is one-dimensional, and two dozen
# bearings cover a whole coastline. Rejection sampling over the disc, which is
# how zones are placed, would spend nearly every attempt proposing sites the
# shore rule was always going to refuse.
#
# Bearings are strided by the golden angle from a seeded start rather than swept
# uniformly. A uniform sweep walks a contiguous arc, so on an island whose whole
# south side is course every early attempt lands in the same rejected region and
# the good ground on the north shore is not reached until the sweep gets there.
#
# THE THREE RULES ARE NOT EQUAL and are not scored together into one number.
#
#   * CLEARING THE COASTLINE is a hard requirement — a crater cut through the
#     contour tears the cliff sweep that hangs off it — so a candidate that fails
#     it is discarded outright, and an island where every bearing fails it simply
#     carries no crater.
#   * CLEARING THE COURSE is a gate with a fallback. Among the candidates that
#     clear it the choice is made on looks; if NONE of them do, the least-zoned
#     wins anyway, so a hub whose shoreline is entirely spoken for still gets its
#     crash site rather than none.
#   * BEING IN A WOOD is the preference that then picks between the survivors,
#     and it has no threshold at all: the most wooded candidate wins even on an
#     island where that is not very wooded.
#
# THAT ORDER IS LOAD-BEARING, and it is why the wood is a ranking rather than a
# fourth hard rule. The first two are about the ground being TORN or the feature
# reading as a course decoration; the third is only about the picture. A site in
# a clearing is a worse crash site, not a broken one.
#
# WHAT THE WOOD BUYS. The rule this replaced took the first candidate that
# cleared the course and stopped, which is a rule about search order rather than
# about ground — and on the shipped hub it landed on bare shore: 0.00 forest
# under the bowl and 0.06 in the collar, so the burning ring of trees the whole
# `fire_scatter` crown system exists to stand had nothing to stand in. Ranking
# the same survivors by `crater_forest_score`, over eight seeds:
#
#                              forest   collar   inland
#   shore 0.17, first clear      0.25     0.23    276 m   <- what shipped
#   shore 0.17, most wooded      0.63     0.50    245 m
#   shore 0.30, first clear      0.42     0.42    341 m
#   shore 0.30, most wooded      0.75     0.67    365 m   <- ships now
#
# THE TWO LEVERS ARE INDEPENDENT AND THEY COMPOSE, and the diagonal is the point:
# moving the contour inland without ranking still lands on whatever cleared
# first, and ranking without moving it is ranking a set the coastline has already
# thinned to eleven. Neither alone gets there.
#
# The collar is the row to watch rather than the forest column — it is the ground
# that ends up ON FIRE, and tests/PROBE_crater_ring.gd counts what actually
# stands in it: 197 plants alight before, 1,783 after.
#
# IT COSTS THE EARLY-OUT, which is the honest price of ranking rather than
# taking. The old rule could stop on its first or second bearing; this one must
# see all 24 to know which is best, so the coast ring is now always paid in full
# — 102 ms on the hub — and the scoring adds 87 ms on top of it (25 points on
# each of 23 survivors, measured by tests/PROBE_crater_forest_samples.gd). It is
# paid once per island per worker clone and cached on the island forever, which
# is the same budget `CRATER_RING_SAMPLES` was sized against.
func _place_crater(isl: Island) -> Crater:
	if not crater_enabled or crater_radius <= 0.0:
		return null
	if isl.radius < crater_min_radius:
		return null
	if crater_hub_only and not isl.is_hub:
		return null

	var rng := RandomNumberGenerator.new()
	rng.seed = (isl.cell.x * 51787) ^ (isl.cell.y * 92173) ^ world_seed ^ 0x0C4A7E

	# The zones have to exist before the crater can be told to avoid them. Safe
	# to ask for here: `zones_for` never asks for a crater back, so the two caches
	# build in one direction only.
	var zones := zones_for(isl)
	var zi: Array = [ZONE_ROUGH, 0.0, 0, 1e9, 0.0]

	var outer := crater_outer_radius()
	# The EXCAVATED radius, not the painted one — see `crater_bowl_radius`.
	var bowl_r := crater_bowl_radius()
	var want_mask := crater_shore_target(isl)

	var start := rng.randf() * TAU
	# The two answers, kept apart: the most wooded site that clears the course,
	# and — only if nothing does — the least-zoned site that clears the coast.
	var wooded: Crater = null
	var wooded_score := -1.0
	var best: Crater = null
	var best_zone := 1e9
	for i in range(clampi(crater_place_attempts, 4, 64)):
		var ang := start + float(i) * CRATER_BEARING_STRIDE
		var dir := Vector2(cos(ang), sin(ang))
		var ring := _shore_ring_radius(isl, dir, want_mask)
		if ring <= 0.0:
			continue
		var centre := isl.center + dir * ring

		# Sampled on a ring at the edge of the EXCAVATION for the coastline, and
		# at the full painted radius for the zones — the two rules protect against
		# different things and are checked at the radius each actually reaches.
		# Both quantities fall off monotonically outward from the crater, so a
		# clear ring means a clear interior.
		#
		# DENSELY, not the eight points this had first. The 176 m ring the crater
		# had then, 1,080 m out, subtended about 19 degrees of bearing, and with
		# `coast_jagged` the shore wobble is indexed BY bearing — so eight samples
		# stepped 2.3 degrees at a time through a noise field that moves inside
		# that, and they walked straight past the notch that failed the margin. The
		# cost is once per island, forever, which is why the count was left where
		# it is when the crater shrank.
		var coast := 1e9
		var zone_w := zone_at(centre.x, centre.y, zones, zi)
		for j in range(CRATER_RING_SAMPLES):
			var a := TAU * float(j) / float(CRATER_RING_SAMPLES)
			var dq := Vector2(cos(a), sin(a))
			var qb := centre + dq * bowl_r
			var qo := centre + dq * outer
			coast = minf(coast, mask_for(isl, qb.x, qb.y))
			zone_w = maxf(zone_w, zone_at(qo.x, qo.y, zones, zi))
		if coast < crater_coast_margin:
			continue

		# The ship came in off the sea, so it was travelling INLAND — the gouge
		# points away from the shore it crossed, and the far wall it piled its
		# ejecta against is the one further up the island.
		var yaw := deg_to_rad(rng.randf_range(-crater_heading_spread, crater_heading_spread))
		var c := Crater.new()
		c.center = centre
		c.radius = crater_radius
		c.heading = (-dir).rotated(yaw)
		c.outer = outer
		# The datum the floor is pinned to — see `Crater.floor_base_y`. Taken with
		# no zone influence on purpose: `crater_zone_max` already keeps the crash
		# site off the fairways, so the ground under it is wild by construction, and
		# reading a zone here would mean the floor's level depended on a golf hole
		# it is not allowed to be near.
		c.floor_base_y = base_height(centre.x, centre.y,
				mask_for(isl, centre.x, centre.y), isl)
		if zone_w <= crater_zone_max:
			# Scored only here, never on the fallback branch: a candidate that is
			# sitting in a fairway is not competing on looks, and the score is by
			# far the most expensive thing in the loop.
			var wood := crater_forest_score(isl, centre, zones)
			if wood > wooded_score:
				wooded_score = wood
				wooded = c
		elif zone_w < best_zone:
			best_zone = zone_w
			best = c
	return wooded if wooded != null else best


# How many points a divot candidate's outer ring is tested at.
#
# LOWER THAN `CRATER_RING_SAMPLES` (192) AND FOR A STATED REASON, because the
# temptation with a number like this is to copy the careful one next door and
# stop thinking. What that count is really sized against is the ANGULAR span the
# footprint subtends at the island's shore wobble: the crater's 48 m bowl at
# ~1,080 m out spans about 5 degrees of bearing, and the wobble is indexed by
# bearing, so the ring has to be sampled fine enough to catch a notch inside
# that. The divot's bowl is 15 m — under a third of the span — so 64 points step
# finer along the coastline than 192 do for the crater and are converged by the
# same argument. They also cost a third as much on a search that runs more
# bearings.
const DIVOT_RING_SAMPLES := 64


# Where the escape pod came down.
#
# THE SEARCH IS THE CRATER'S, WITH TWO RULES ADDED AND ONE SWAPPED. Added: the
# centre has to be `divot_crater_clearance` from the crash site, which is the
# "a ways away" requirement and the only reason this is not simply a second
# crater. Swapped: candidates are ranked by DISTANCE FROM THE SHIP rather than
# by how wooded they are. The crater wants deep forest because a burning collar
# needs trees to burn; the pod wants nothing in particular from the ground it
# lands on, and the one thing it does want is to be somewhere else. The second
# added rule is `divot_hill_rise`: the ground has to still be climbing past the
# dent, which is what gives the bank something behind it to hold the pod up.
#
# AND "SOMEWHERE ELSE" IS THE NEAREST SOMEWHERE ELSE, which is the ranking's
# second version and the opposite of its first. Furthest-wins was the obvious
# reading of "a ways away" and it is the wrong one: with the clearance rejecting
# everything close, the ranking then went and picked the most distant bearing
# left, and the two halves of one event ended up 1,643 m apart on an island 2.5 km
# across — the pod on one shore, the ship on the other, nothing to connect them.
# The distance rule belongs entirely to `divot_crater_clearance` and the search's
# job is to OBEY it rather than to maximise it, so the incumbent is beaten from
# below and the pod comes down as close to its ship as the standoff allows.
#
# THE HEADING IS UPHILL, NOT OFFSHORE. The crater takes its heading from the
# coast because the ship crossed the shore and kept going; the pod was thrown
# clear and came down under a chute, so which way it was travelling when it hit
# is not a story the shoreline tells. What has to be true is that it stopped
# against RISING GROUND, so the heading is read off the local gradient and the
# bank is cut where the hill already goes up. See `_divot_heading`.
func _place_divot(isl: Island) -> Divot:
	if not divot_enabled or divot_radius <= 0.0:
		return null
	# NO SHIP, NO POD. This is also what makes every crash-site switch govern the
	# divot without any of them being restated: no crater on satellites, none on
	# islands under `crater_min_radius`, none at all with `crater_enabled` off.
	var crater := crater_for(isl)
	if crater == null:
		return null

	var rng := RandomNumberGenerator.new()
	rng.seed = (isl.cell.x * 51787) ^ (isl.cell.y * 92173) ^ world_seed ^ 0x0D07E7

	var zones := zones_for(isl)
	var zi: Array = [ZONE_ROUGH, 0.0, 0, 1e9, 0.0]

	var outer := divot_outer_radius()
	# The EXCAVATED radius for the coastline, the painted one for the zones — the
	# two rules protect against different things and each is checked at the radius
	# it actually reaches. See `divot_bowl_radius`.
	var bowl_r := divot_bowl_radius()
	var want_mask := divot_shore_target(isl)

	var start := rng.randf() * TAU
	var best: Divot = null
	var best_gap := -1.0
	for i in range(clampi(divot_place_attempts, 4, 64)):
		var ang := start + float(i) * CRATER_BEARING_STRIDE
		var dir := Vector2(cos(ang), sin(ang))
		var ring := _shore_ring_radius(isl, dir, want_mask)
		if ring <= 0.0:
			continue
		var centre := isl.center + dir * ring

		# A WAYS AWAY FROM THE SHIP — the floor, not the target — and checked
		# FIRST because it is the cheapest test in the loop and the one that
		# rejects most bearings. Measured to the crater's centre rather than to
		# its rim, so the export means the distance it says and does not move when
		# the crash site is resized.
		var gap := centre.distance_to(crater.center)
		if gap < divot_crater_clearance:
			continue
		# Ranked before the expensive rules for the same reason: a candidate that
		# cannot beat the incumbent does not need to be checked at all. NEAREST
		# WINS, so the incumbent is beaten from below — and `best_gap` stays at
		# its -1 sentinel rather than being seeded with a huge number, so the
		# first candidate to clear the floor is taken whatever its distance.
		if best_gap >= 0.0 and gap >= best_gap:
			continue

		# ...AND THE HILL HAS TO KEEP GOING. Cheap — one heading (four samples)
		# and one height against the datum the floor is pinned to — and checked
		# before the ring loop for the same reason the gap is checked before this:
		# it rejects a whole class of candidate for a fraction of the cost. See
		# `divot_hill_rise`, which is the number, and the settle it is protecting.
		var head := _divot_heading(isl, centre, dir)
		var base_c := base_height(centre.x, centre.y,
				mask_for(isl, centre.x, centre.y), isl)
		var beyond := centre + head * outer
		if base_height(beyond.x, beyond.y,
				mask_for(isl, beyond.x, beyond.y), isl) - base_c < divot_hill_rise:
			continue

		var coast := 1e9
		var zone_w := zone_at(centre.x, centre.y, zones, zi)
		for j in range(DIVOT_RING_SAMPLES):
			var a := TAU * float(j) / float(DIVOT_RING_SAMPLES)
			var dq := Vector2(cos(a), sin(a))
			var qb := centre + dq * bowl_r
			var qo := centre + dq * outer
			coast = minf(coast, mask_for(isl, qb.x, qb.y))
			zone_w = maxf(zone_w, zone_at(qo.x, qo.y, zones, zi))
		if coast < divot_coast_margin:
			continue
		# NO FALLBACK BRANCH, unlike `_place_crater`. That one keeps a
		# least-zoned candidate in reserve because an island with no crash site
		# at all has no inciting incident and the scene loses its subject. An
		# island with no pod on it has a crash site and reads fine; a pod parked
		# in a bunker does not. So the zone rule is hard here and the honest
		# answer to "nowhere clear" is null.
		if zone_w > divot_zone_max:
			continue

		var dv := Divot.new()
		dv.center = centre
		dv.radius = divot_radius
		dv.heading = head
		dv.outer = outer
		# The datum the floor is pinned to. Sampled above, as `base_c`, because
		# the hill rule needs the same number and the two must not be allowed to
		# disagree; taken with no zone influence for the reason `_place_crater`
		# takes its the same way: `divot_zone_max` already keeps the dent off the
		# course, so the ground under it is wild by construction and reading a
		# zone here would make the floor's level depend on a fairway it is not
		# allowed to be near.
		dv.floor_base_y = base_c
		# What the pod actually stands on. At the centre the trough is pinned at
		# full depth — `bowl` is exactly 1 inside `divot_floor_frac` and the skid
		# term is 1 at `along` 0 — so the floor is the datum less the depth, with
		# no noise fetch in it. Stored rather than re-derived so the placer and
		# the mesher cannot disagree by a wobble sample.
		dv.floor_y = dv.floor_base_y - divot_depth
		best_gap = gap
		best = dv
	return best


# Which way the pod was travelling: UPHILL, from the local gradient.
#
# Four height samples on a cross `divot_uphill_span` wide, once per island. The
# gradient of the base surface points up the hill by definition, and that is the
# direction the bank has to be in — the pod ran into rising ground and stopped
# against it, so the scarp `divot_at` cuts at the far end is cut where the ground
# was already going up. Aim it any other way and the bank is a mound heaped on a
# flat field, which is the exact thing that reads as scenery.
#
# SAMPLED ON `base_height` AND NOT ON THE FINISHED SURFACE, which matters: the
# finished surface includes the divot, and asking the divot which way it should
# face would be circular. It also excludes zones, for the reason the floor datum
# does.
#
# THE FALLBACK IS INLAND. On genuinely flat ground the gradient is noise and
# normalising it would aim the pod at whichever way a rounding error fell. Inland
# — away from the shore the candidate bearing came from — is the one direction
# that is always defensible: it is the way the island rises on average, and it is
# the way something arriving off the sea was going.
func _divot_heading(isl: Island, centre: Vector2, dir: Vector2) -> Vector2:
	var s := maxf(divot_uphill_span, 1.0) * 0.5
	var hx0 := base_height(centre.x - s, centre.y,
			mask_for(isl, centre.x - s, centre.y), isl)
	var hx1 := base_height(centre.x + s, centre.y,
			mask_for(isl, centre.x + s, centre.y), isl)
	var hz0 := base_height(centre.x, centre.y - s,
			mask_for(isl, centre.x, centre.y - s), isl)
	var hz1 := base_height(centre.x, centre.y + s,
			mask_for(isl, centre.x, centre.y + s), isl)
	var grad := Vector2(hx1 - hx0, hz1 - hz0)
	# A tenth of a metre across the span — a gradient under 0.7% — is flat by any
	# reading, and below it the direction is the noise floor rather than the hill.
	if grad.length() < 0.1:
		return -dir
	return grad.normalized()


# Distance from an island's centre to where the land mask reads `target`, along a
# unit bearing. Negative if there is no such crossing.
#
# SCAN THEN BISECT, and the bracket is exact rather than guessed. The mask is
# `1 - d/R + wobble * coast_irregularity` with the wobble bounded by 1, so the
# level is crossed somewhere inside
#
#     R * (1 - target - coast_irregularity)  ..  R * (1 - target + coast_irregularity)
#
# and the mask is above the target at the inner end and below it at the outer one
# for every bearing. This cannot miss the level and it cannot wander off the
# island looking for it.
#
# In `coast_jagged` mode — which is both shipped presets — the wobble is indexed
# by BEARING alone, so along a fixed ray the mask is exactly linear in `d` and
# the first bracket the scan finds is already the answer to within one step. The
# scan is there for the positional-wobble mode, where the mask along a ray is not
# monotone and a straight bisection over the whole bracket could converge on the
# wrong crossing — the outer one, past a notch in the shore.
func _shore_ring_radius(isl: Island, dir: Vector2, target: float) -> float:
	var irr := maxf(coast_irregularity, 0.0)
	var lo := maxf(isl.radius * (1.0 - target - irr), 0.0)
	var hi := isl.radius * (1.0 - target + irr)
	if hi <= lo:
		return -1.0

	var a := lo
	var b := hi
	var found := false
	var fa := mask_for(isl, isl.center.x + dir.x * a, isl.center.y + dir.y * a) - target
	for i in range(1, 25):
		var q := lerpf(lo, hi, float(i) / 24.0)
		var fq := mask_for(isl, isl.center.x + dir.x * q, isl.center.y + dir.y * q) - target
		if fa >= 0.0 and fq < 0.0:
			b = q
			found = true
			break
		a = q
		fa = fq
	if not found:
		return -1.0
	# Fourteen halvings of a bracket that starts under half the island wide, so
	# this lands the contour to well under a metre — a good deal finer than the
	# 2 m vertex grid the crater is drawn on.
	for _i in range(14):
		var mid := (a + b) * 0.5
		if mask_for(isl, isl.center.x + dir.x * mid, isl.center.y + dir.y * mid) - target >= 0.0:
			a = mid
		else:
			b = mid
	return (a + b) * 0.5


# ------------------------------------------------------------ the ruin entrance

## The ruin entrance's clearing, built on first ask and cached on the island.
##
## THE ORDER THE STAMPS ARE PLACED IN RUNS ONE WAY, and this is its far end: zones,
## then the crater (which avoids them), then the divot (which is placed from the
## crater), then this (which is placed from the divot). Every call below here asks
## upstream and nothing upstream ever asks for a ruin — which is why `_place_ruin`
## samples `base_height` directly and never goes through `sample`, whose landform
## includes the ruin and would ask for the site it is in the middle of choosing.
##
## ON A RING (`ruin_ring_count` above 0) this is the FIRST entrance, and every one
## of them is built here at once; `ruins_for` has the rest.
func ruin_for(isl: Island) -> RuinSite:
	if isl == null:
		return null
	if not _ready:
		prepare()
	if not isl.ruin_built:
		if ruin_ring_count > 0:
			isl.ruins = _place_ruin_ring(isl)
		else:
			var one := _place_ruin(isl)
			isl.ruins = [] if one == null else [one]
		isl.ruin = null if isl.ruins.is_empty() else isl.ruins[0]
		isl.ruin_built = true
	return isl.ruin


## Every entrance's clearing on an island, in placement order — empty, the one
## `ruin_for` returns, or the whole ring. The island's own array: read it, do not
## change it.
func ruins_for(isl: Island) -> Array:
	if isl == null:
		return []
	ruin_for(isl)
	return isl.ruins


## The clearing NEAREST a point, or null on an island with none — which is the only
## one whose `ruin_at` can be anything but zero there, and so the one `sample` and
## the scatters ask for.
##
## NEAREST IS ENOUGH, because no two clearings can reach the same ground: a ring
## keeps its sites further apart than two footprints and a gap
## (`_ruin_ring_clear`), so wherever one clearing's weight is above zero every
## other one's centre is further away. Asked per sample, so the one-site case —
## every island but a ringed one — costs one array size.
func ruin_near(isl: Island, x: float, z: float) -> RuinSite:
	if isl == null:
		return null
	if not isl.ruin_built:
		ruin_for(isl)
	if isl.ruins.size() <= 1:
		return isl.ruin
	var p := Vector2(x, z)
	var best: RuinSite = null
	var best_d2 := INF
	for s in isl.ruins:
		var site: RuinSite = s
		var d2 := site.center.distance_squared_to(p)
		if d2 < best_d2:
			best_d2 = d2
			best = site
	return best


## The clearings whose footprints reach an XZ rectangle — none, one, or on a
## rectangle wide enough to span the gap between two, several. For the mesher,
## which hoists the ruin once per chunk on this and falls back to `ruin_near` per
## vertex only when it gets more than one. Same conservative test as its divot's:
## the rectangle's nearest point against the footprint's outer radius.
func ruins_in_rect(isl: Island, min_x: float, min_z: float, max_x: float,
		max_z: float) -> Array:
	var out: Array = []
	for s in ruins_for(isl):
		var site: RuinSite = s
		var near := Vector2(clampf(site.center.x, min_x, max_x),
				clampf(site.center.y, min_z, max_z))
		if near.distance_squared_to(site.center) < site.outer * site.outer:
			out.append(site)
	return out


## Radius past which the clearing moves nothing: the flat core plus the band.
func ruin_outer_radius() -> float:
	return maxf(ruin_flat_radius, 0.0) + maxf(ruin_slope_band, 0.0)


## The clearing at a point, as (height offset in METRES, levelling weight 0..1).
##
## `base_h` is the ground the offset is added to — the zoned base height, exactly
## what `base_height` returned for this point — and the offset is the fraction
## `weight` of the way from there to the plane. So inside the core, where the
## weight is exactly 1, the sum is `floor_y` to the last bit whatever hill it
## replaced; across the band it eases back; past `outer` it is nothing. There is no
## third shape anywhere in it, and that is what "flatten the terrain using the
## masked area" means once it is written down.
##
## A LERP TOWARD A PLANE, NOT AN OFFSET BY A CONSTANT, and that is the whole
## difference from the crater. A bowl cut a fixed depth into a hillside follows the
## hillside — that is the bug `Crater.floor_base_y` was added to patch after the
## fact. This is pinned to its datum from the first line, so there is nothing to
## patch: the hill does not get a say inside the disc.
##
## TWO CHANNELS, NOT THREE, and a Vector2 rather than the impacts' Vector3 because
## this is not one of them — the mesher does not treat the ruin as a feature on top
## of the ground, it folds it INTO the ground (see `RuinSite`), so there is no
## shared shape to keep.
##
## The weight is what the scatters clear by and what the splat grooms by: 1 across
## the core, a smoothstep down to 0 at `outer`. It is gated on the coastline the
## way every stamp here is — `_place_ruin` keeps the footprint at least
## `ruin_coast_margin` inland, where the gate reads exactly 1, so on a placed site
## it is the brace to that belt and changes nothing.
func ruin_at(x: float, z: float, mask: float, ruin: RuinSite, base_h: float) -> Vector2:
	if ruin == null:
		return Vector2.ZERO
	var d2 := ruin.center.distance_squared_to(Vector2(x, z))
	# Early out on the footprint, squared so the common case costs no sqrt — this
	# runs per vertex and four more times per vertex for the neighbours.
	if d2 >= ruin.outer * ruin.outer:
		return Vector2.ZERO
	var w := 1.0
	if d2 > ruin.radius * ruin.radius:
		w = 1.0 - smoothstep(ruin.radius, ruin.outer, sqrt(d2))
	w *= smoothstep(0.0, maxf(ruin_coast_margin, 0.001), mask)
	return Vector2((ruin.floor_y - base_h) * w, w)


## How WORN the ground looks, from `ruin_at`'s levelling weight — what the splat
## grooms by, and only the splat. See `ruin_wear_wobble` for why the two differ.
##
## Zero wherever the levelling weight is, so this never costs its noise fetch off
## the footprint and never paints ground the clearing did not touch.
func ruin_wear(x: float, z: float, levelling: float) -> float:
	if levelling <= 0.0:
		return 0.0
	if ruin_wear_wobble <= 0.0:
		return levelling
	return clampf(levelling + ruin_wear_wobble * _ruin_wear_noise.get_noise_2d(x, z),
			0.0, 1.0)


# Candidate rings are this far apart, in metres, and each carries this many
# bearings.
#
# SIZED AGAINST THE FOOTPRINT, which is what a candidate is standing in for. At
# 10 m between rings and 32 bearings, neighbouring candidates are at most 20 m
# apart anywhere inside the 200 m band — under half the footprint's 46 m radius,
# so two neighbours share most of the ground they are judged on and a site that
# clears every rule cannot fall between them. Finer buys positions nobody could
# tell apart and costs the search on every worker clone.
const RUIN_RING_STEP := 10.0
const RUIN_BEARINGS := 32
# Points on the footprint's outer ring checked for the coastline and the zones.
#
# FAR FEWER THAN `CRATER_RING_SAMPLES`, and for the reason that note gives for
# needing so many: that count is sized to catch a notch in a jagged shore sitting
# right on the crater's margin. The ruin's margin is `zone_coast_margin`, some
# three hundred metres inland of any shore on the hub, where the jag is a smooth
# swell; and the zone weight it also tests varies over `zone_noise_scale` (70 m),
# so 48 points on a 46 m ring step six metres at a time through a field that moves
# over seventy.
const RUIN_FOOT_SAMPLES := 48
# Metres between samples along the walk from the start, for the zone rule and the
# sight line both. A hole's grooming stays above `ruin_zone_max` across at least
# 80 m of it — a 14 m par 3 at its narrowest wobble, plus nine tenths of its 34 m
# apron either side — so an 8 m step cannot step over one.
const RUIN_LINE_STEP := 8.0
# Metres a ring entrance moves along its bearing per try, in and out alternately.
# Half the start-side search's ring step, because here it is the ONLY freedom a site
# has: the bearing is fixed, so a coarse step is a site that stands ten metres further
# off the ring than the ground needed it to.
const RUIN_SLIDE_STEP := 5.0


# Where the ruin entrance stands: THE NEAREST OPEN GROUND TO THE PLAYER START THAT
# CAN BE LEVELLED WITHOUT DIGGING A QUARRY.
#
# THE SEARCH IS THE DIVOT'S SHAPE TURNED INSIDE OUT. That one walks bearings out
# from the island's centre to a shore contour; this walks RINGS out from the pod,
# nearest first, because the requirement is to be near the start and the first
# ring that holds an acceptable site is by construction the nearest one. Each ring
# carries `RUIN_BEARINGS` candidates, offset by half a step on alternate rings so
# no bearing is looked down twice. The whole search stops on the first ring that
# answers, which is also what keeps it cheap: on the shipped hub the first three
# rings are inside the pod's reach and fall to one distance each, the fourth
# answers, and the whole placement costs about 23 ms on top of the zones, the crater
# and the pod it depends on.
#
# THE RULES ARE NOT EQUAL, and they are not summed into a score — the crater's
# argument, and the same three tiers:
#
#   * HARD, discarded outright: inside the walk band; clear of the crash site and
#     the pod's dent by `ruin_feature_gap`; inland by `ruin_coast_margin`; off every
#     zone by `ruin_zone_max`, footprint AND the walk to it; and levelled by no more
#     than `ruin_earthwork_max`. A ruin on a fairway, over a cliff, in the pod's
#     dent or in a quarry is a broken ruin.
#   * A GATE WITH A FALLBACK: open ground. The site and the sight line from the
#     start must both carry no more than `ruin_open_forest` of wood. A candidate
#     that fails only this is remembered, not discarded — if NO ring holds open
#     ground, the nearest wooded one wins, because a ruin in a clearing cut out of a
#     forest is a worse landmark and still a landmark, and an island with no
#     entrance to its dungeon is a worse island than either.
#   * A PREFERENCE that picks within the answering ring: the LEAST earthwork. Every
#     candidate on a ring is the same walk from the pod, so what separates them is
#     how little the ground has to be moved — the gentlest of the near sites, not
#     the gentlest site on the island.
#
# NEAREST, NOT FLATTEST, is the ranking and it is the divot's lesson — though on the
# shipped hub the two agree, which is worth saying before arguing for either: the
# nearest open site is also the flattest open site anywhere in the band. So the
# choice is about the next retune rather than this one. Ranked by flatness, the site
# is free to wander to the far edge of the band for a few centimetres less
# earthwork, and "near the start" stops being a rule and becomes a coincidence of
# the seed; ranked by nearness, flatness still gets its say through the cap and
# within the ring. The earthwork cap is what stops nearest from meaning steep, so
# the two never have to be traded in one number.
#
# ON THE SHIPPED HUB it lands 90 m SOUTH-WEST of the pod, on the open ground between
# the edge of the wood the pod came down in and the lip of hole 1's basin: of the
# 32 bearings on that ring, 12 reach hole 1's bank, 15 would have to move more than
# 3 m of ground, 3 are wooded and 2 are open, and the gentler of those two wins at
# 2.55 m. The line of sight back to the pod crosses only the few trees at the wood's
# edge. `tests/PROBE_ruin_site.gd` prints the search, ring by ring.
func _place_ruin(isl: Island) -> RuinSite:
	if not ruin_enabled or ruin_flat_radius <= 0.0:
		return null
	# NO POD, NO START, NO RUIN — and asking for the divot is also what builds the
	# crater and the zones behind it, so every stamp this has to avoid exists by
	# the time it is looked at.
	var divot := divot_for(isl)
	if divot == null:
		return null
	var crater := crater_for(isl)
	var zones := zones_for(isl)
	var zi: Array = [ZONE_ROUGH, 0.0, 0, 1e9, 0.0]
	var start := divot.center
	var outer := ruin_outer_radius()

	# A seeded spin on the bearings, so the candidates do not all line up on the
	# world's axes and the pattern differs between islands. Nothing else here is
	# random.
	var rng := RandomNumberGenerator.new()
	rng.seed = (isl.cell.x * 51787) ^ (isl.cell.y * 92173) ^ world_seed ^ 0x2E1A5
	var spin := rng.randf() * TAU

	var fallback: RuinSite = null
	var fallback_ring := -1
	var rings := int(floor(maxf(ruin_start_max - ruin_start_min, 0.0) / RUIN_RING_STEP)) + 1
	for ri in range(rings):
		var dist := maxf(ruin_start_min, 0.0) + float(ri) * RUIN_RING_STEP
		var best: RuinSite = null
		for k in range(RUIN_BEARINGS):
			var ang := spin + TAU * (float(k) + 0.5 * float(ri % 2)) / float(RUIN_BEARINGS)
			var c := start + Vector2(cos(ang), sin(ang)) * dist
			# Cheapest first: two distances, then a ring of mask-and-zone samples,
			# then the walk — and only then the sight line and the survey, which are
			# where the cost is.
			if c.distance_to(divot.center) - divot.outer - outer < ruin_feature_gap:
				continue
			if crater != null \
					and c.distance_to(crater.center) - crater.outer - outer < ruin_feature_gap:
				continue
			if not _ruin_footprint_clear(isl, c, outer, zones, zi):
				continue
			if not _ruin_path_clear(start, c, zones, zi):
				continue
			var open := _ruin_openness(isl, start, c, divot.outer) <= ruin_open_forest
			# A wooded candidate is only worth surveying while it could still be
			# the fallback: none found yet, or one found on THIS ring that it might
			# beat on earthwork. A later ring is further from the start and can never
			# displace a fallback from an earlier one.
			if not open and fallback != null and fallback_ring != ri:
				continue
			var site := _ruin_survey(isl, c, zones, zi)
			if site == null:
				continue
			site.heading = (start - c).normalized()
			site.anchor = start
			site.open = open
			if open:
				if best == null or site.earthwork < best.earthwork:
					best = site
			elif fallback == null or site.earthwork < fallback.earthwork:
				fallback = site
				fallback_ring = ri
		if best != null:
			return best
	return fallback


# Where a RING of entrances stands: `ruin_ring_count` of them at even bearings round
# the island's centre, every door facing it.
#
# THE BEARINGS ARE FIXED AND THE RADIUS IS NOT. An even ring is the brief, so entrance
# k stands on the bearing `ruin_ring_spin + 360 k / N` and on no other, and its door
# faces straight back down that bearing at the centre. What gives is the distance: the
# entrance walks along its own bearing from the ring, `RUIN_SLIDE_STEP` at a time and
# in and out alternately, and stands on the first ground the rules accept — the nearest
# acceptable ground to the ring on that line, and of two equally near, the one that
# moves less earth. Nothing within `ruin_ring_slide` and that bearing stands empty;
# `SCRIPT_ruin_site.gd` says so when it counts them.
#
# THE RULES ARE `_place_ruin`'s HARD ONES, with the earthwork cap swapped for the
# ring's own: clear of the crash site and the pod by `ruin_feature_gap`, and of every
# entrance already placed by the same; inland by `ruin_coast_margin`; off every zone
# by `ruin_zone_max`; levelled by no more than `ruin_ring_earthwork_max`. Not the walk
# from the start or the openness gate — those are what "near the start" means, and
# a ring is near nothing but its centre. A site in a wood is kept, and `open` records
# that it is one.
#
# ON THE SHIPPED HUB — seven entrances, 800 m out, first bearing 0.75 degrees — every
# entrance lands, the furthest 30 m off the ring. `tests/PROBE_ruin_ring.gd` prints
# the ring, entrance by entrance, and sweeps the spins and radii it was chosen from.
func _place_ruin_ring(isl: Island) -> Array:
	var sites: Array = []
	if not ruin_enabled or ruin_flat_radius <= 0.0 or ruin_ring_count <= 0:
		return sites
	# Asked first for `_place_ruin`'s reason: this builds the zones and the crater
	# behind them, so every stamp the ring has to avoid exists by the time it looks.
	var divot := divot_for(isl)
	var crater := crater_for(isl)
	var zones := zones_for(isl)
	var zi: Array = [ZONE_ROUGH, 0.0, 0, 1e9, 0.0]
	var outer := ruin_outer_radius()
	var ring := isl.radius * ruin_ring_radius
	var tries := int(floor(maxf(ruin_ring_slide, 0.0) / RUIN_SLIDE_STEP))
	var n := ruin_ring_count
	for k in range(n):
		var ang := deg_to_rad(ruin_ring_spin) + TAU * float(k) / float(n)
		var dir := Vector2(cos(ang), sin(ang))
		var site: RuinSite = null
		for ti in range(tries + 1):
			for sgn in ([0.0] if ti == 0 else [-1.0, 1.0]):
				var off: float = float(sgn) * float(ti) * RUIN_SLIDE_STEP
				if ring + off <= 0.0:
					continue
				var c := isl.center + dir * (ring + off)
				if not _ruin_ring_clear(isl, c, outer, crater, divot, sites, zones, zi):
					continue
				var s := _ruin_survey(isl, c, zones, zi, ruin_ring_earthwork_max)
				if s == null:
					continue
				if site == null or s.earthwork < site.earthwork:
					s.slide = off
					site = s
			if site != null:
				break
		if site == null:
			continue
		site.heading = -dir
		site.anchor = isl.center
		site.index = k
		site.open = _ruin_core_forest(isl, site.center) <= ruin_open_forest
		sites.append(site)
	return sites


# The hard rules a ring site has to pass before it is surveyed: `_place_ruin`'s gaps
# to the crash site and the pod, the same gap to every entrance already standing, and
# `_ruin_footprint_clear`. Cheapest first, as there.
func _ruin_ring_clear(isl: Island, c: Vector2, outer: float, crater: Crater,
		divot: Divot, placed: Array, zones: Array, zi: Array) -> bool:
	if divot != null and c.distance_to(divot.center) - divot.outer - outer < ruin_feature_gap:
		return false
	if crater != null and c.distance_to(crater.center) - crater.outer - outer < ruin_feature_gap:
		return false
	for p in placed:
		var other: RuinSite = p
		if c.distance_to(other.center) - other.outer - outer < ruin_feature_gap:
			return false
	return _ruin_footprint_clear(isl, c, outer, zones, zi)


# Is the whole footprint inland and off the zones? Tested on its outer ring, which
# is sufficient for the reason `_place_crater` gives: both quantities fall off
# monotonically away from what they measure — the mask toward the coast, the zone
# weight away from the zone — so the point of the disc nearest either is on its
# rim, and a clear rim is a clear disc. The centre is asked too, which costs one
# sample and covers a zone small enough to sit wholly inside the ring.
func _ruin_footprint_clear(isl: Island, c: Vector2, outer: float, zones: Array,
		zi: Array) -> bool:
	if zone_at(c.x, c.y, zones, zi) > ruin_zone_max or zi[4] > ruin_zone_max:
		return false
	for j in range(RUIN_FOOT_SAMPLES):
		var a := TAU * float(j) / float(RUIN_FOOT_SAMPLES)
		var q := c + Vector2(cos(a), sin(a)) * outer
		if mask_for(isl, q.x, q.y) < ruin_coast_margin:
			return false
		# BOTH weights: the grooming (the course) and the flatten (the land, which
		# a golf hole's skirt widens by 40 m). The footprint must not share ground
		# with either — the flatten because two levellings would fight over the
		# same vertices, the grooming because it is the course.
		if zone_at(q.x, q.y, zones, zi) > ruin_zone_max or zi[4] > ruin_zone_max:
			return false
	return true


# Can the site be walked to from the start without setting foot on a zone?
#
# THIS IS THE GOLF WALL'S RULE, written in the field's own terms. The wall
# (`SCRIPT_golf_wall.gd`) goes up round a hole the moment the player is inside its
# capsule plus `wall_margin` (14 m), and it is solid from the inside — so a walk
# that crosses a hole is a walk that ends on it until the player dismisses the
# shield. The field does not know `wall_margin` and should not: it knows the
# GROOMING, which a hole's wall stands well inside. The wall is 14 m outside the
# un-wobbled half-width and the grooming falls off from the wobbled one, over an
# apron of 34..55 m; worked through every half-width the sampler can make, the
# grooming AT the wall never drops below 0.44 (the worst is a 17 m fairway with the
# wobble pulled a quarter in), and it falls monotonically outward. So a straight
# walk that never sees more than `ruin_zone_max` of it passes every wall with most
# of an apron to spare. `tests/TEST_ruin_site.gd` checks the walk against the real
# wall's capsule as well, with the real margin.
#
# Build pads and paths count too. Nothing walls them, but a route to a landmark
# that runs across somebody's building plot is not a route the ranking should
# prefer, and it costs nothing to keep the rule one rule.
func _ruin_path_clear(start: Vector2, c: Vector2, zones: Array, zi: Array) -> bool:
	var steps := maxi(int(ceil(start.distance_to(c) / RUIN_LINE_STEP)), 1)
	for t in range(steps + 1):
		var q := start.lerp(c, float(t) / float(steps))
		if zone_at(q.x, q.y, zones, zi) > ruin_zone_max:
			return false
	return true


# How WOODED a candidate is, 0..1: the larger of the mean forest over the flat
# core and the mean forest along the sight line from the start.
#
# THE LARGER, because each half is a separate way of failing the brief. A site in
# open ground behind a wood is invisible from the pod; a site in a wood with open
# ground between is a hole in a forest. Either one alone is not a clearing near the
# start.
#
# THE LINE RUNS FROM THE DENT'S EDGE TO THE DISC'S — the ground between the two
# features, which is where anything in the way would stand. Inside the dent is the
# pod and the bank it leans on, and inside the disc the ruin's own clearing: neither
# is a wood the view has to get through.
#
# ASKED OF `forest_at` WITH NO SLOPE, which makes it an upper bound — the canopy
# only thins on ground steeper than 0.29 — and an upper bound is the right side to
# err on for a claim of "you can see it from here". It is also what keeps this
# off `sample`, which cannot be called during placement (see `ruin_for`), and it
# is one noise fetch a point.
func _ruin_openness(isl: Island, start: Vector2, c: Vector2, from_r: float) -> float:
	var r := maxf(ruin_flat_radius, 0.0)
	var site := _ruin_core_forest(isl, c)
	var line := 0.0
	var m := 0
	var span := start.distance_to(c) - from_r - r
	if span > 0.0:
		var dir := (c - start).normalized()
		var steps := maxi(int(ceil(span / RUIN_LINE_STEP)), 1)
		for t in range(steps + 1):
			var q := start + dir * (from_r + span * float(t) / float(steps))
			line += forest_at(q.x, q.y, mask_for(isl, q.x, q.y), 0.0)
			m += 1
		line /= maxf(float(m), 1.0)
	return maxf(site, line)


# The mean forest over a candidate's flat core: the centre and rings at half and all
# of the radius, 25 points. `_ruin_openness`'s first half, and on a ring the whole of
# what `RuinSite.open` records.
func _ruin_core_forest(isl: Island, c: Vector2) -> float:
	var r := maxf(ruin_flat_radius, 0.0)
	var site := 0.0
	var n := 0
	for ri in range(3):
		var rr := r * float(ri) / 2.0
		var nb := 1 if ri == 0 else 8 * ri
		for k in range(nb):
			var a := TAU * float(k) / float(nb)
			var q := c + Vector2(cos(a), sin(a)) * rr
			site += forest_at(q.x, q.y, mask_for(isl, q.x, q.y), 0.0)
			n += 1
	return site / maxf(float(n), 1.0)


# Level a candidate: where its plane goes, and how far that moves the ground.
# Null if it moves anything further than `ruin_earthwork_max`.
#
# THE PLANE IS THE AREA-WEIGHTED MEAN of the ground the disc replaces, sampled on
# rings at thirds of the radius and weighted by radius so each ring stands for the
# annulus it sits in. The MEAN because it balances the cut against the fill: on
# a site that falls one way the uphill half is cut into and the downhill half is
# built up by the same amount, which is the smallest the worst of the two can be
# and the least bank the band then has to carry. The crater and the divot pin to
# the ground at their centre instead, and for a bowl that is fine — the rim is the
# ground either way. For a plane it is not: on a hillside whose centre sits on a
# local hummock, the whole disc would be sunk or raised by the hummock.
#
# THE EARTHWORK is the largest |ground - plane| over the core and the band both,
# with the band sampled at its middle and its rim. Taken against the ZONED base —
# the ground the mesher actually has before the ruin is folded in — though a
# footprint that cleared `ruin_zone_max` has almost no zone in it to see.
#
# `cap` is the earthwork cap to hold it to; negative is `ruin_earthwork_max`, and a
# ring passes its own (`ruin_ring_earthwork_max`).
func _ruin_survey(isl: Island, c: Vector2, zones: Array, zi: Array,
		cap := -1.0) -> RuinSite:
	if cap < 0.0:
		cap = ruin_earthwork_max
	var r := maxf(ruin_flat_radius, 0.0)
	var band := maxf(ruin_slope_band, 0.0)
	var core: Array[float] = []
	var sum := 0.0
	var wsum := 0.0
	for ri in range(4):
		var rr := r * float(ri) / 3.0
		var nb := 1 if ri == 0 else 6 * ri
		# The centre stands for the innermost sixth of the radius; every ring for
		# the annulus around it, hence weighting by its own radius.
		var w := r / 6.0 if ri == 0 else rr
		for k in range(nb):
			var a := TAU * float(k) / float(nb)
			var q := c + Vector2(cos(a), sin(a)) * rr
			var h := _ruin_ground(isl, q, zones, zi)
			core.append(h)
			sum += h * w
			wsum += w
	var plane := sum / maxf(wsum, 1e-6)
	var worst := 0.0
	for h in core:
		worst = maxf(worst, absf(h - plane))
	for rr in [r + band * 0.5, r + band]:
		for k in range(16):
			var a := TAU * float(k) / 16.0
			var q := c + Vector2(cos(a), sin(a)) * float(rr)
			worst = maxf(worst, absf(_ruin_ground(isl, q, zones, zi) - plane))
			if worst > cap:
				return null
	if worst > cap:
		return null
	var site := RuinSite.new()
	site.center = c
	site.radius = r
	site.outer = r + band
	site.floor_y = plane
	site.earthwork = worst
	return site


# The ground a candidate is levelled against: the zoned base height, which is what
# the mesher holds in `gbase` before the ruin is folded in. See `_ruin_survey`.
func _ruin_ground(isl: Island, q: Vector2, zones: Array, zi: Array) -> float:
	zone_at(q.x, q.y, zones, zi)
	return base_height(q.x, q.y, mask_for(isl, q.x, q.y), isl, zi[4], zi[1])


# ------------------------------------------------------------------- forest

## Forest weight in 0..1 at a point: 1 deep inside a wood, 0 on open ground.
##
## Read by BOTH the tree scatter (how thickly to plant) and the splat (needle
## litter under the canopy), which is why it lives here rather than in either.
## Two consumers of one noise cannot disagree about where the wood is; two noises
## would, and the ground would go brown a hundred metres from the nearest tree.
##
## Suppressed inside zones by `zone_flat`, so a fairway is never wooded and the
## grooming rules in `splat_weights` never have to fight this one.
func forest_at(x: float, z: float, mask: float, slope: float,
		zone_flat := 0.0) -> float:
	if not forest_enabled:
		return 0.0
	var iso := 1.0 - 2.0 * clampf(forest_coverage, 0.0, 1.0)
	var f := smoothstep(iso, iso + forest_edge, _forest_noise.get_noise_2d(x, z))
	f *= 1.0 - smoothstep(forest_max_slope * FOREST_SLOPE_KNEE, forest_max_slope, slope)
	f *= smoothstep(0.0, maxf(forest_coast_margin, 0.001), mask)
	return f * (1.0 - clampf(zone_flat, 0.0, 1.0))


# Final surface height: base terrain with the crash crater stamped in and the
# bunker dished out. The bunker's rim term peaks at s = 0.5 -- the trap's own
# edge -- which is what makes it read as a scooped hollow rather than a painted
# patch; the crater arrives already in metres, shaped by `crater_at`.
#
# The two are ADDED rather than ordered, and nothing arbitrates between them
# because in practice they never meet: a bunker only exists inside a golf zone
# and a crater is placed on wild ground outside every zone, with `crater_zone_max`
# and `sand_rough_gain` guarding each end of that. If either is ever relaxed the
# sum is still the honest answer -- a trap dug into a crater floor is a trap dug
# into a crater floor -- so this stays a sum rather than a priority.
#
# THE POD'S DIVOT IS A THIRD TERM ON THE SAME SUM, and it is a separate parameter
# rather than something the caller folds into `crater_lift` because the two are
# separately meaningful to everything upstream: the mesher gates a crater-aware
# shading normal on `crater_near` and a divot-aware one on `divot_near`, and a
# single pre-summed lift would leave it unable to tell which of the two it was
# standing in. `divot_crater_clearance` keeps them hundreds of metres apart, so
# in practice at most one is ever non-zero -- and if that is ever relaxed, a dent
# in a crater floor is a dent in a crater floor, which is the same argument the
# bunker gets.
func surface_height(base_h: float, sand: float, crater_lift := 0.0,
		divot_lift := 0.0) -> float:
	var h := base_h + crater_lift + divot_lift
	if sand <= 0.0:
		return h
	var dish := sand * sand * (3.0 - 2.0 * sand)
	var lip := 4.0 * sand * (1.0 - sand)
	return h - sand_depth * dish + sand_rim * lip * lip


# ---------------------------------------------------------------- splat rules

## The slope band rock fades in over — onset in `x`, fully rock by `y`.
##
## Ask this rather than reading `rock_slope_lo`/`_hi`, which are only the manual
## fallback: with `rock_follows_veg` on (the default) the band comes from
## `forest_max_slope` and the exports are inert. `splat_weights` reads a copy
## resolved in `prepare()`, so this is for tests, tools and anything setting a
## slope limit that has to agree with the ground's own.
func rock_band() -> Vector2:
	if not rock_follows_veg:
		return Vector2(rock_slope_lo, rock_slope_hi)
	var hi := maxf(forest_max_slope, 0.001)
	return Vector2(hi * FOREST_SLOPE_KNEE, hi)


# Negated discrete Laplacian, normalised by the sampling distance: how far the
# centre sits ABOVE the average of its four neighbours, per metre of that
# distance. Positive on ridges and rims, negative in hollows and gullies.
static func curvature(h: float, hx0: float, hx1: float, hz0: float, hz1: float,
		d: float) -> float:
	return (4.0 * h - (hx0 + hx1 + hz0 + hz1)) / (2.0 * maxf(d, 0.001))

# The four surface weights, normalised, given slope and curvature.
#
# `convexity` is `curvature()` above -- positive on ridges and rims, negative in
# hollows and gullies. That's the "concave / convex" term: soil and silt collect
# where water would pool, bare rock is exposed where the ground is proud, and the
# slope rule handles cliffs.
#
# Returns Color(grass, soil, rock, sand) so it drops straight into vertex COLOR.
func splat_weights(slope: float, convexity: float, sand: float, mask: float,
		zone_flat := 0.0, zone_kind := ZONE_ROUGH, forest := 0.0,
		crater := 0.0, divot := 0.0, ruin := 0.0) -> Color:
	# The band is resolved in `prepare()`, not here: this runs per vertex on the
	# mesher's workers, and `rock_band()` is a function call plus a Vector2 per
	# vertex to return two numbers that cannot change between them.
	if not _ready:
		prepare()
	var rock := smoothstep(_rock_lo, _rock_hi, slope)
	# Proud ground scours down to rock even where it isn't steep -- but only as a
	# dressing (`rock_convex_gain`), because the convexity term reads the finest
	# octave of the hill noise and would otherwise grey over every wrinkle.
	rock = maxf(rock, smoothstep(0.0, maxf(rock_convexity, 0.001), convexity)
			* clampf(rock_convex_gain, 0.0, 1.0))
	# Bare rock lip at the cliff edge, fading inland.
	if coast_rock_width > 0.0:
		rock = maxf(rock, 1.0 - smoothstep(0.0, coast_rock_width, mask))
	var soil := smoothstep(0.0, maxf(soil_concavity, 0.001), -convexity) * (1.0 - rock)
	var grass := maxf(1.0 - rock - soil, 0.0)

	# Needle litter under a canopy: a fraction of the turf becomes bare floor.
	# Done in the four channels that already exist rather than by adding a fifth,
	# for exactly the reason the build pads use `soil` -- it costs no vertex
	# attribute and no change to the textured shader. The flat-colour shader in
	# SCENE_test_zone_W2 additionally gets the raw weight in UV2 so it can tint
	# the two channels toward a distinct forest palette.
	if forest_litter > 0.0:
		var litter := clampf(forest, 0.0, 1.0) * forest_litter * (1.0 - rock)
		var moved := grass * litter
		grass -= moved
		soil += moved

	# Zones are groomed ground, and WHICH surface they groom to is how the player
	# reads the land: mown turf means golf, cleared earth means you can build
	# here. That costs nothing — `soil` is already one of the four splat channels,
	# so labelling buildable ground needs no fifth channel, no extra vertex
	# attribute and no shader change.
	var f := clampf(zone_flat, 0.0, 1.0)
	if zone_kind == ZONE_GOLF:
		var g := f * fairway_grooming
		grass = lerpf(grass, 1.0, g)
		soil = lerpf(soil, 0.0, g)
		rock = lerpf(rock, 0.0, g)
	elif zone_kind == ZONE_BUILD:
		var g := f * pad_grooming
		soil = lerpf(soil, 1.0, g)
		grass = lerpf(grass, 0.0, g)
		rock = lerpf(rock, 0.0, g)
	elif zone_kind == ZONE_PATH:
		# A track is worn earth, so it grooms to the same channel a pad does; the
		# two are told apart in the shader by UV2, not here.
		var g := f * path_grooming
		soil = lerpf(soil, 1.0, g)
		grass = lerpf(grass, 0.0, g)
		rock = lerpf(rock, 0.0, g)

	# THE RUIN'S CLEARING, worn toward bare earth the way a pad is groomed to it —
	# by `ruin_grooming`, which ships at 0 because the meadow has grown back over
	# it: on the shipped hub this does nothing and the disc keeps its turf. `ruin`
	# arrives as `ruin_wear`, NOT the levelling weight: the levelling weight
	# wobbled, so for a preset that does wear the ground, the worn edge lobes across
	# the band and turf survives in patches in the core, while still being zero
	# wherever the ground was never touched. See `ruin_wear_wobble`.
	#
	# BEFORE THE IMPACTS, and it is the ordering argument the crater makes about the
	# grooming, one step further back: the ruin is the OLDEST thing on the island,
	# so it is painted first and anything that has happened since paints over it.
	# `ruin_feature_gap` means neither impact ever reaches it; if that were relaxed,
	# a ship that came down on a ruin would leave slag, not a trodden path.
	var rw := clampf(ruin, 0.0, 1.0)
	if rw > 0.0:
		var g := rw * ruin_grooming
		soil = lerpf(soil, 1.0, g)
		grass = lerpf(grass, 0.0, g)
		rock = lerpf(rock, 0.0, g)

	# THE CRASH SITE, and it goes in AFTER the grooming for a reason: a crater cut
	# through a fairway is not a mown fairway with a hole in it, it is a crash
	# site. `crater_zone_max` keeps the two apart so this is very nearly always
	# moot -- but if a site ever does have to be placed on a course, the impact
	# is the more recent event and should win, and the ordering is what says so.
	#
	# THE ANGLE RULE. What the impact did to the ground depends on which way that
	# ground faces, and the split is between BLASTED and DUSTED: the bowl was
	# scoured down to fused substrate, and everything the blast threw came back
	# down as ash on top of whatever it landed on. Slope picks between them, over
	# a band well below the ordinary rock onset -- see `crater_scour_lo`. So the
	# steep inner walls go to fused rock, the lip crest and the ejecta apron
	# outside it go to charred dirt, and the two meet on the shoulder of the rim
	# rather than at a line.
	#
	# The floor is the exception the slope rule cannot cover on its own: it is the
	# flattest ground in the whole feature and it is also the part that actually
	# took the impact, so `crater_fuse_weight` fuses it whatever its angle. That
	# is what puts a melted crust in the bottom of the bowl instead of a dirt
	# floor with scoured walls above it.
	#
	# Classified from the LANDFORM slope, like everything else here -- the crater
	# cannot repaint its own walls, for exactly the reason a bunker cannot.
	#
	# `crater` ARRIVES RAW — the radial weight, not `crater_burn` of it. The two
	# levels below are levels on that curve and have to be read against the same
	# one `crater_rim_paint` sits on; only the final lerp wants the remap.
	var cw := clampf(crater, 0.0, 1.0)
	if cw > 0.0:
		# Slope may only scour DOWN IN THE BOWL. See `crater_scour_floor`; the
		# short version is that the lip's inner face is as steep as the wall's,
		# and the lip is the one part of a crater that must not scour.
		var inside := smoothstep(crater_scour_floor,
				minf(crater_scour_floor + crater_scour_floor_width, 1.0), cw)
		var scour := maxf(
				smoothstep(crater_scour_lo, maxf(crater_scour_hi, crater_scour_lo + 0.001), slope)
					* inside,
				smoothstep(clampf(crater_fuse_weight, 0.0, 1.0), 1.0, cw))
		var burn := crater_burn(cw)
		grass = lerpf(grass, 0.0, burn)
		soil = lerpf(soil, 1.0 - scour, burn)
		rock = lerpf(rock, scour, burn)

	# THE POD'S DIVOT, and it is the crash site's rule with the fire taken out.
	# Same shape -- torn ground goes to bare earth, and the steep part of it goes
	# to stone -- and the differences are all the ones that follow from nothing
	# having burnt here:
	#
	#   * NO FUSE TERM. The crater's floor melts whatever its angle, because it
	#     is the part that took the impact. A pod's floor is packed dirt, so the
	#     only thing that shows stone is ground that was actually CUT, which is
	#     what the slope band says on its own.
	#   * NO SCOUR GATE either, and for the mirror of that reason. The crater
	#     needs `crater_scour_floor` to stop its LIP scouring, because a lip is
	#     thrown ejecta that must read as loose. This bank is not thrown, it is
	#     scarped -- ground cut into and pushed up -- so its face showing stone
	#     is the correct answer rather than the one being guarded against.
	#   * A NARROWER SLOPE BAND, sitting lower. See `divot_scarp_lo`.
	#
	# `divot` ARRIVES RAW, like `crater` above and for the identical reason: the
	# band below is a level on the radial curve, and only the final lerp wants
	# `divot_scuff`'s remap.
	#
	# AFTER THE CRATER, on the ordering argument the crater itself makes about
	# the grooming: the later event wins. `divot_crater_clearance` means the two
	# never actually meet, so this is very nearly always moot -- but if it is
	# ever relaxed, the pod came to rest after the ship came down.
	var dw := clampf(divot, 0.0, 1.0)
	if dw > 0.0:
		var scarp := smoothstep(divot_scarp_lo,
				maxf(divot_scarp_hi, divot_scarp_lo + 0.001), slope)
		var torn := divot_scuff(dw)
		grass = lerpf(grass, 0.0, torn)
		soil = lerpf(soil, 1.0 - scarp, torn)
		rock = lerpf(rock, scarp, torn)

	# Sand wins outright where a trap is: it's a dug hollow, not a blend.
	var keep := 1.0 - clampf(sand, 0.0, 1.0)
	var c := Color(grass * keep, soil * keep, rock * keep, clampf(sand, 0.0, 1.0))
	var sum := c.r + c.g + c.b + c.a
	if sum < 1e-5:
		return Color(1, 0, 0, 0)
	return Color(c.r / sum, c.g / sum, c.b / sum, c.a / sum)


# ------------------------------------------------------------------ gameplay

## Single-point query for game code (ball friction, hole placement, spawn picking).
## Costs five height evaluations, so it's for occasional use — the mesher uses the
## grid path in `SCRIPT_chunk_mesher.gd` instead, which shares work between neighbours.
##
## Returns:
##   on_land  : bool   — false means open void, and the other fields are unset
##   height   : float  — surface height in logical world Y
##   normal   : Vector3— of the FINAL surface, bunker dish included
##   slope    : float  — 0 flat .. 1 vertical, from that same normal
##   weights  : Color  — grass, soil, rock, sand
##   surface  : String — the dominant one of those four
##   forest   : float  — 0 open ground .. 1 deep inside a wood
##   island   : Island — the island this point belongs to
##   zone     : String — "golf", "build", "path" or "rough"
##   flatten  : float  — 0 in the hills .. 1 in a zone's core. THE COURSE's
##                       weight: how groomed the ground is. This is the one
##                       gameplay wants, and the one the scatters keep their
##                       vegetation out of.
##   ground_flatten : float — the LAND's weight, `flatten` widened by the golf
##                       skirt. Equal to `flatten` everywhere but a golf zone's
##                       collar. Only `base_height` and things checking the
##                       terrain's shape want this; see `zone_skirt`.
##   hole     : String — the id of the hole underfoot, or "" if none
##   crater   : float  — 0 off the crash site .. 1 on its fused floor
##   divot    : float  — 0 off the pod's dent .. 1 on its floor
##   ruin     : float  — 0 off every ruin's clearing .. 1 on a levelled core.
##                       What the scatters keep their plants off; see `ruin_at`.
##   buildable: bool   — flat cleared ground the player may build on
func sample(x: float, z: float) -> Dictionary:
	if not _ready:
		prepare()
	var islands := islands_at(x, z)
	var owner_slot: Array = [null]
	var mask := mask_at(x, z, islands, owner_slot)
	var owner: Island = owner_slot[0]
	if mask <= 0.0 or owner == null:
		return {"on_land": false}

	# Central differences for slope and curvature, at the same world distance the
	# mesher uses, so a gameplay query and the vertex under it agree. The zone
	# influence has to be evaluated at each offset too, or the four neighbours
	# would be read off the un-flattened surface and a fairway would report the
	# slope of the hill it replaced.
	var zones := zones_for(owner)
	var zi: Array = [ZONE_ROUGH, 0.0, 0, 1e9, 0.0]
	var d := maxf(curvature_radius, 0.01)
	var flat := zone_at(x, z, zones, zi)
	var kind: int = zi[0]
	var lift: float = zi[1]
	var ground_flat: float = zi[4]
	var h := base_height(x, z, mask, owner, ground_flat, lift)
	# THE RUIN'S CLEARING IS PART OF THE LANDFORM, so it goes in here, before a
	# single slope or neighbour is taken — and into every neighbour below, through
	# `_zoned_height`, for the same reason a zone does. Folded in afterwards, a
	# levelled disc cut into a hillside would report the hillside's slope: the
	# forest would thin, the rock rule would read scree and the ball would roll
	# on ground that is plainly flat. See `RuinSite`. The NEAREST clearing, which on
	# an island with a ring of them is the only one that can reach this point or any
	# of the four neighbours a curvature-radius away — see `ruin_near`.
	var ruin := ruin_near(owner, x, z)
	var ru := ruin_at(x, z, mask, ruin, h)
	h += ru.x
	var hx0 := _zoned_height(x - d, z, islands, owner, zones, ruin)
	var hx1 := _zoned_height(x + d, z, islands, owner, zones, ruin)
	var hz0 := _zoned_height(x, z - d, islands, owner, zones, ruin)
	var hz1 := _zoned_height(x, z + d, islands, owner, zones, ruin)

	# The LANDFORM normal, off the pre-bunker surface. Slope and curvature taken
	# from it are what classify the ground, so a trap can never repaint its own
	# walls as scree and the splat stays exactly as LOD-stable as it was.
	var n := Vector3((hx0 - hx1) / (2.0 * d), 1.0, (hz0 - hz1) / (2.0 * d)).normalized()
	var base_slope := clampf(1.0 - n.y, 0.0, 1.0)
	var convexity := curvature(h, hx0, hx1, hz0, hz1, d)

	var sand := sand_at(x, z, mask, base_slope, flat, kind, zi[3])
	var forest := forest_at(x, z, mask, base_slope, flat)
	var crater := crater_for(owner)
	# `h` is handed over so the floor can be pinned to its datum — see `crater_at`.
	var cr := crater_at(x, z, mask, crater, h)
	var divot := divot_for(owner)
	var dv := divot_at(x, z, mask, divot, h)
	var w := splat_weights(base_slope, convexity, sand, mask, flat, kind, forest,
			cr.y, dv.y, ruin_wear(x, z, ru.y))

	# The SURFACE normal, off the dished-out ground the ball actually rolls on.
	# Only worth deriving where a trap or a crater can exist; everywhere else the
	# two are the same expression, since `surface_height` is the identity at
	# sand = 0 and crater lift = 0.
	#
	# The crater matters here more than the bunkers do. A 13.5 m bowl reported
	# with the slope of the hillside it was cut into is a ball that rolls the
	# wrong way down a wall you can plainly see, and this is the query the golf
	# physics reads.
	# The divot joins that list on the same argument at a smaller scale. It is a
	# 1.2 m trough with a 2.6 m bank at one end, which is well inside what a ball
	# notices and is the whole of what the pod is standing on — reported with the
	# hillside's slope, the bank would be a wall you can see and roll straight up.
	var slope := base_slope
	if sand_possible(flat, kind) or crater_near(x, z, crater, d) \
			or divot_near(x, z, divot, d):
		var sx0 := _sand_surface(x - d, z, islands, owner, zones, base_slope, crater, divot,
				ruin)
		var sx1 := _sand_surface(x + d, z, islands, owner, zones, base_slope, crater, divot,
				ruin)
		var sz0 := _sand_surface(x, z - d, islands, owner, zones, base_slope, crater, divot,
				ruin)
		var sz1 := _sand_surface(x, z + d, islands, owner, zones, base_slope, crater, divot,
				ruin)
		n = Vector3((sx0 - sx1) / (2.0 * d), 1.0, (sz0 - sz1) / (2.0 * d)).normalized()
		slope = clampf(1.0 - n.y, 0.0, 1.0)

	var names := ["grass", "soil", "rock", "sand"]
	var vals := [w.r, w.g, w.b, w.a]
	var top := 0
	for i in range(1, 4):
		if vals[i] > vals[top]:
			top = i

	# Naming is thresholded even though blending is not — see `zone_label_min`.
	var zone_name := "rough"
	var hole_id := ""
	var named := flat >= zone_label_min
	if named and kind == ZONE_GOLF:
		zone_name = "golf"
		hole_id = "%d:%d:%d" % [owner.cell.x, owner.cell.y, int(zi[2])]
	elif named and kind == ZONE_BUILD:
		zone_name = "build"
	elif named and kind == ZONE_PATH:
		zone_name = "path"

	return {
		"on_land": true,
		"height": surface_height(h, sand, cr.x, dv.x),
		"normal": n,
		"slope": slope,
		"weights": w,
		"surface": names[top],
		"forest": forest,
		"island": owner,
		"zone": zone_name,
		"flatten": flat,
		"ground_flatten": ground_flat,
		"hole": hole_id,
		"crater": cr.y,
		"molten": cr.z,
		"divot": dv.y,
		"ruin": ru.y,
		"buildable": kind == ZONE_BUILD and flat >= buildable_flatten and sand < 0.5
				and cr.y <= 0.0 and dv.y <= 0.0,
	}


# Pre-sand height with the zone influence applied, for the curvature neighbours —
# and with the ruin's clearing levelled in when one is passed, which `sample` does
# and `crater_forest_score` must not: that one runs while the crater is being
# placed, the ruin is placed from the pod and the pod from the crater, and asking
# for the ruin there would ask for a site whose placement is waiting on this call.
func _zoned_height(x: float, z: float, islands: Array, owner: Island,
		zones: Array, ruin: RuinSite = null) -> float:
	var zi: Array = [ZONE_ROUGH, 0.0, 0, 1e9, 0.0]
	zone_at(x, z, zones, zi)
	var m := mask_at(x, z, islands)
	var h := base_height(x, z, m, owner, zi[4], zi[1])
	return h + ruin_at(x, z, m, ruin, h).x


# Final surface height at a neighbour -- bunker dish and crater both -- for the
# surface normal above.
#
# `slope` is the CENTRE point's landform slope, deliberately reused rather than
# re-derived here: `sand_at` only wants it to suppress traps on hillsides, it
# varies over hundreds of metres while a bunker is tens across, and re-deriving
# it would cost four more height evaluations per neighbour. Reusing it also keeps
# the result a pure function of (centre, neighbour), which is what lets two
# chunks sharing a vertex compute bit-identical normals for it.
func _sand_surface(x: float, z: float, islands: Array, owner: Island,
		zones: Array, slope: float, crater: Crater = null,
		divot: Divot = null, ruin: RuinSite = null) -> float:
	var zi: Array = [ZONE_ROUGH, 0.0, 0, 1e9, 0.0]
	var flat := zone_at(x, z, zones, zi)
	var m := mask_at(x, z, islands)
	var h := base_height(x, z, m, owner, zi[4], zi[1])
	# The landform first, exactly as `sample` builds its centre — see there.
	h += ruin_at(x, z, m, ruin, h).x
	return surface_height(h, sand_at(x, z, m, slope, flat, zi[0], zi[3]),
			crater_at(x, z, m, crater).x, divot_at(x, z, m, divot).x)


## Convenience: surface height at a point, or `fallback` over the void.
func height_at(x: float, z: float, fallback := -1e9) -> float:
	var s := sample(x, z)
	return s["height"] if s["on_land"] else fallback


## The LANDFORM's height at a point on `isl`, or `fallback` off it: the zoned ground
## with the nearest ruin's clearing levelled in — `sample`'s height before a bunker,
## the crash site or the pod's dent is dished into it, with no normal and no splat.
## The island is the caller's, as it is the mesher's: the ground this returns is the
## ground `SCRIPT_chunk_mesher.gd` builds for that island, off the same `mask_for`.
##
## THE SAME NUMBER AS `height_at` WHEREVER NONE OF THOSE THREE IS, which is everywhere
## round a ruin — its placement keeps the footprint off every zone and clear of both
## impacts — and several times cheaper, because `sample` takes four more heights only
## to difference them into a normal, and finds its island itself. For
## `SCRIPT_ruin_site.gd`, which seats the ruin's own plants on the ground past its
## disc, hundreds of them a ruin; `tests/TEST_ruin_gap_growth.gd` holds every one of
## those plants to `height_at`.
func landform_height(isl: Island, x: float, z: float, fallback := -1e9) -> float:
	if isl == null:
		return fallback
	if not _ready:
		prepare()
	var m := mask_for(isl, x, z)
	if m <= 0.0:
		return fallback
	var zi: Array = [ZONE_ROUGH, 0.0, 0, 1e9, 0.0]
	zone_at(x, z, zones_for(isl), zi)
	var h := base_height(x, z, m, isl, zi[4], zi[1])
	return h + ruin_at(x, z, m, ruin_near(isl, x, z), h).x


## Is this point land at all — the LANDMASS MASK ALONE, with none of the height,
## slope, zone, bunker, crater and splat work `sample` does around it. Same
## answer as `sample(x, z)["on_land"]` and around thirty times cheaper, because
## the mask is a handful of distances plus one noise lookup while `sample` is
## five heights, four of them only to difference into a normal.
##
## IT EXISTS FOR EDGE PROBES. Anything that has to stay a stated number of metres
## INSIDE the coastline — the roaming encounter blobs are the first — cannot read
## that off one sample, because the mask is "fraction of the way from coast to
## centre" and not a distance: the metres a mask value is worth depend on the
## island's radius and on how hard the coast wobble is biting at that bearing. So
## the honest test is to ask about a ring of points at the margin you want, which
## is a query you want to be able to afford several of.
func is_land(x: float, z: float) -> bool:
	if not _ready:
		prepare()
	return mask_at(x, z, islands_at(x, z)) > 0.0


# ---------------------------------------------------------------------- golf

## A hole's tee as a point on the ground, in LOGICAL world space.
func hole_tee(h: Hole) -> Vector3:
	return Vector3(h.tee.x, height_at(h.tee.x, h.tee.y, 0.0), h.tee.y)


## A hole's pin as a point on the ground, in LOGICAL world space.
func hole_pin(h: Hole) -> Vector3:
	return Vector3(h.pin.x, height_at(h.pin.x, h.pin.y, 0.0), h.pin.y)


## A dogleg's elbow as a point on the ground, in LOGICAL world space. Returns the
## midpoint of tee and pin for a straight hole, so a caller that ignores `bent`
## still gets a point ON the axis rather than a stray origin.
func hole_bend(h: Hole) -> Vector3:
	var p := h.bend if h.bent else (h.tee + h.pin) * 0.5
	return Vector3(p.x, height_at(p.x, p.y, 0.0), p.y)


## Every hole whose island's footprint reaches an XZ rect. Scans the same
## lattice neighbourhood `islands_in_rect` does, so it is as cheap as asking
## which islands are nearby — the holes themselves are already cached on them.
func holes_in_rect(min_x: float, min_z: float, max_x: float, max_z: float) -> Array:
	var out: Array = []
	for entry in islands_in_rect(min_x, min_z, max_x, max_z):
		out.append_array(holes_for(entry))
	return out


## Every hole with a tee or pin within `radius` of a logical XZ point, nearest
## tee first. This is the "what can I play from here" query.
func holes_near(x: float, z: float, radius: float) -> Array:
	var p := Vector2(x, z)
	var out: Array = []
	for entry in holes_in_rect(x - radius, z - radius, x + radius, z + radius):
		var h: Hole = entry
		if minf(p.distance_to(h.tee), p.distance_to(h.pin)) <= radius:
			out.append(h)
	out.sort_custom(func(a: Hole, b: Hole):
			return p.distance_squared_to(a.tee) < p.distance_squared_to(b.tee))
	return out


## The hole whose tee is closest to a logical XZ point within `radius`, or null.
func nearest_hole(x: float, z: float, radius := 2000.0) -> Hole:
	var near := holes_near(x, z, radius)
	return near[0] if not near.is_empty() else null
