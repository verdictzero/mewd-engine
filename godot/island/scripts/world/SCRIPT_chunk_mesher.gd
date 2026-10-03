class_name IslandChunkMesher
extends RefCounted

# Turns a rectangle of `IslandField` into surface arrays. Pure and static, so it
# runs on a worker thread with no engine state involved — the caller hands it a
# per-thread `IslandField.clone()` and gets back arrays ready for
# `ArrayMesh.add_surface_from_arrays`.
#
# The chunk is a grid, but NOT a plain heightmap. A heightmap can only fall as
# fast as its vertex spacing allows, so a plunging coastline would come out as a
# ramp of stretched triangles instead of a cliff. Instead the land mask is
# CONTOURED:
#
#   * cells fully on land               -> two triangles, as usual
#   * cells fully over the void         -> nothing at all
#   * cells the coastline runs through  -> clipped to the exact zero-crossing of
#     the mask, by Sutherland–Hodgman against the mask as a half-plane test
#
# That gives a crisp shoreline instead of a stair-stepped one, and it hands us
# the coastline as a set of segments — which is exactly what the rim needs. Each
# coastline segment is then swept downward into the void along a profile with two
# halves: a SHOULDER that leaves the shore at a shallow angle and steepens
# asymptotically to vertical, and a WALL that plunges from there, converging on
# the island's centre axis and closing to a single point far below the fog. See
# `_build_rim` for why those two halves end up in different meshes.
#
# This assumes an island's coastline is star-shaped about its centre (radius
# single-valued in angle) so the converging sweep doesn't self-intersect. The
# `coast_irregularity` cap keeps that true — the same overhang-free assumption
# `SCRIPT_procedural_island.gd` already makes about its profile.
#
# TWO PRECISION RULES hold the seams together. Both matter, and neither is
# obvious from looking at the output:
#
#  1. Sample coordinates are ALWAYS derived as `base + (chunk_index * cells +
#     grid_index - pad) * step` from the island's own base corner. Letting each
#     chunk start from its own precomputed origin would be algebraically
#     identical and numerically not: two chunks could land a shared edge on
#     floats that differ in the last bit, the mask would differ, and the
#     contour would tear along the join.
#
#  2. A zero-crossing is always interpolated from the LOWER grid index to the
#     higher one (see `_crossing`), because `a + t*(b-a)` and `b + (1-t)*(a-b)`
#     agree in real arithmetic but not in floats.
#
# Vertices come out RELATIVE to `pivot` (the island's centre axis) rather than in
# absolute world space: logical coordinates grow without bound as you fly, and
# Vector3 stores 32-bit floats, so absolute positions would slowly lose
# millimetres. The subtraction happens in GDScript's 64-bit floats before the
# Vector3 is built, so the stored value keeps full relative precision.

## Floor on rings emitted per cliff terrace. `IslandField.cliff_wall_rings_min`
## is what actually bounds the wall now; this survives as the floor the field
## applies when reading `cliff_rings_per_terrace`.
const _MIN_CLIFF_RINGS := 2

## Half-width, in metres, of the central difference `_coast_out` takes the
## coastline's facing from. See that function.
##
## NOT A TUNING KNOB, as it turns out. `tests/PROBE_rim_normals.gd` sweeps it
## from 0.5 m to 8 m — a full contour cell — and the answer moves by half a
## degree in the mean and 0.4 degrees in the sample-to-sample jitter. The coast
## wobble is three octaves of simplex over hundreds of metres, so there is no
## fine structure down here for the difference to catch. Set at a quarter of the
## 8 m contour cell because that is the width that describes the geometry the
## mesher actually sweeps.
const COAST_NORMAL_EPS := 2.0

## The smallest torn weight worth spending UV2.x on. See the write site.
##
## A hundredth, and it is a VISIBILITY threshold rather than a numerical one: the
## divot's grade moves the soil layer by `divot_break` (0.45) at full weight, so a
## hundredth of that is under half a percent of one channel's brightness — well
## inside one step of the sixteen-level palette LUT the whole scene is quantised
## through, which is to say invisible by construction rather than by judgement.
const _SCUFF_MIN := 0.01


# Build one chunk of one island.
#
# `base_x` / `base_z` are the island footprint's minimum corner, `ci` / `cj` the
# chunk's index within that footprint, `cells` the grid resolution (vertex
# spacing is `size / cells`). `pivot` is subtracted from every emitted vertex.
#
# Returns {} when the chunk holds no land, otherwise:
#   top         : Array — the walkable surface AND the rim's shoulder, one mesh
#                         (also used for collision)
#   cliff_bands : Array — one {arrays, aabb} per vertical band of the wall,
#                         top-most first; empty if this chunk holds no coastline
#   aabb        : AABB  — bounds relative to `pivot`, the wall included
#   aabb_top    : AABB  — the surface's own bounds, shoulder included
#   aabb_cliff  : AABB  — every band merged
static func build(field: IslandField, isl: IslandField.Island, base_x: float,
		base_z: float, ci: int, cj: int, size: float, cells: int,
		pivot: Vector3, want_cliffs := true) -> Dictionary:
	var n := maxi(cells, 1)
	var step := size / float(n)

	# Curvature must be measured over a fixed WORLD distance or the splat changes
	# when a chunk swaps LOD — which is exactly what a coarse chunk of the hub
	# does, and it turns its grass grey.
	#
	# When the grid is finer than that distance, the neighbours we want are
	# already on it, so pad by that many steps and read them for free. When the
	# grid is COARSER (any distant LOD), no grid neighbour is close enough and the
	# field has to be asked directly. That costs four extra evaluations per
	# vertex, but only ever at the LODs that have few vertices to begin with.
	var d := maxf(field.curvature_radius, 0.001)
	var r := 1
	var probe := true
	if step <= d:
		r = maxi(1, int(round(d / step)))
		d = float(r) * step
		probe = false

	var g := n + 1 + 2 * r          # grid points per side, padding included

	# Zones (golf holes, build pads) that can reach this chunk, resolved ONCE for
	# the whole grid. The island carries twenty-odd of them and a 128 m chunk
	# overlaps nought to two, so this turns a per-vertex loop over every zone on
	# the island into a loop over almost none.
	var zones := field.zones_in_rect(isl,
			base_x + float(ci * n - r) * step, base_z + float(cj * n - r) * step,
			base_x + float((ci + 1) * n + r) * step, base_z + float((cj + 1) * n + r) * step)

	# The crash site, resolved once for the whole grid the same way. There is at
	# most one per island and it is cached on it, so this is a field read rather
	# than a query -- but it still wants hoisting, because `crater_at` takes it as
	# an argument and the alternative is fetching it per vertex.
	var crater := field.crater_for(isl)
	# And the pod's dent, hoisted for the identical reason. It is placed
	# `divot_crater_clearance` from the crash site, so on any one chunk at most
	# one of the two is ever in reach -- but which one that is varies by chunk,
	# so both are resolved here and both early-out on a squared distance.
	var divot := field.divot_for(isl)

	# Sample coordinates, shared by every consumer below. See precision rule 1:
	# the integer `ci * n + gi - r` is what makes two chunks agree exactly on the
	# grid line they share.
	var gx := PackedFloat64Array()
	var gz := PackedFloat64Array()
	gx.resize(g)
	gz.resize(g)
	for i in range(g):
		gx[i] = base_x + float(ci * n + i - r) * step
		gz[i] = base_z + float(cj * n + i - r) * step

	# THE DIVOT IS 20 m ACROSS ON A 2.5 km ISLAND, so on all but a handful of the
	# 1,328 chunks the answer to every per-vertex divot question is zero. Dropped
	# to null where the footprint cannot reach this chunk at all, which turns
	# three GDScript calls per vertex into three null compares — and this loop runs
	# some six million times over a prewarm.
	#
	# WORTH DOING BECAUSE THE PREWARM HAS NO HEADROOM. `tests/TEST_world_pregen.gd`
	# caps the build at 4,000 frames and it was already landing at 3,200-3,750 of
	# them under llvmpipe before this feature existed; the divot's per-vertex work
	# added about 150 and started tipping runs over the cap. The crater is 180 m
	# and reaches far more chunks, so the same trick there would buy much less.
	#
	# Nearest point of the padded chunk rect to the divot's centre, against its
	# long-axis radius — the same conservative test `divot_near` makes per vertex,
	# made once.
	if divot != null:
		var near_x := clampf(divot.center.x, gx[0], gx[g - 1])
		var near_z := clampf(divot.center.y, gz[0], gz[g - 1])
		if Vector2(near_x, near_z).distance_squared_to(divot.center) \
				>= divot.outer * divot.outer:
			divot = null

	# The ruin entrance's clearing, hoisted and culled on exactly the divot's
	# argument: it is 92 m across on a 2.5 km island, so all but a handful of chunks
	# drop it here and pay one null compare a vertex for it.
	#
	# IT GOES INTO `gbase`, NOT INTO `surface_height`, and that is the one thing
	# about it this file has to get right. See `IslandField.RuinSite`: a levelled
	# clearing is the LANDFORM, so every slope, curvature, normal and splat below
	# has to be taken off the levelled ground — which they are, for free, the moment
	# the base height they are all differenced from already has it in.
	#
	# AN ISLAND CAN CARRY A RING OF THEM (`IslandField.ruin_ring_count`), hundreds of
	# metres apart, so a chunk almost always reaches none and never more than one —
	# which is the hoisted case. `ruins` is kept for the chunk that does reach two,
	# which needs a rectangle wider than the gap between two footprints: there each
	# vertex asks for its own nearest, `_ruin_at_point`, and the fast path is untouched.
	var ruins := field.ruins_in_rect(isl, gx[0], gz[0], gx[g - 1], gz[g - 1])
	var ruin: IslandField.RuinSite = ruins[0] if ruins.size() == 1 else null
	if ruins.size() < 2:
		ruins = []

	var total := g * g
	var gmask := PackedFloat32Array()
	var gbase := PackedFloat32Array()
	# Zone flatten weight and kind per grid point. Kept alongside the mask because
	# the sand and splat pass below needs them again, and re-deriving them there
	# would double the zone work for no reason.
	var gflat := PackedFloat32Array()
	var gkind := PackedInt32Array()
	# Distance to the nearer end of the dominant zone's axis — for a golf hole,
	# to the tee or the pin. Stored alongside the rest because `sand_at` needs it
	# at the four NEIGHBOURS as well as here, to keep bunkers off the teeing
	# ground; re-deriving it there would mean re-running the whole zone loop.
	var gend := PackedFloat32Array()
	gmask.resize(total)
	gbase.resize(total)
	gflat.resize(total)
	gkind.resize(total)
	gend.resize(total)
	# The clearing's levelling weight per grid point, for the splat — sized only
	# where the clearing reaches this chunk, which is almost nowhere.
	var gruin := PackedFloat32Array()
	if ruin != null or not ruins.is_empty():
		gruin.resize(total)

	# Reused across every grid point: `zone_at` writes into it rather than
	# returning a Dictionary, so the inner loop allocates nothing. Sized 5, which
	# is what asks for slot 4 — the FLATTEN weight, wider than the returned
	# grooming weight by each golf zone's skirt. Only the height below reads it;
	# everything after this loop wants the grooming weight in `gflat`.
	var zi: Array = [IslandField.ZONE_ROUGH, 0.0, 0, 1e9, 0.0]

	var any_land := false
	for gj in range(g):
		var wz := gz[gj]
		var row := gj * g
		for gi in range(g):
			var wx := gx[gi]
			var m := field.mask_for(isl, wx, wz)
			var flat := field.zone_at(wx, wz, zones, zi)
			gmask[row + gi] = m
			gflat[row + gi] = flat
			gkind[row + gi] = zi[0]
			gend[row + gi] = zi[3]
			var b := field.base_height(wx, wz, m, isl, zi[4], zi[1])
			if ruin != null or not ruins.is_empty():
				var rs := ruin if ruins.is_empty() else _ruin_at_point(ruin, ruins, wx, wz)
				var ru := field.ruin_at(wx, wz, m, rs, b)
				b += ru.x
				gruin[row + gi] = ru.y
			gbase[row + gi] = b
			if m > 0.0:
				any_land = true
	if not any_land:
		return {}

	# Per grid point, everything the mesh needs. Only the unpadded interior gets
	# filled — the padding ring exists solely to feed these central differences.
	var gheight := PackedFloat32Array()
	var gnormal := PackedVector3Array()
	var gcolor := PackedColorArray()
	# Zone membership per grid point, carried into ARRAY_TEX_UV. BOTH FLOATS CARRY
	# TWO THINGS, told apart by sign: x = golf grooming weight POSITIVE and the
	# crater's molten core NEGATIVE, y = build-pad grooming weight POSITIVE and
	# crash-crater char NEGATIVE. The stock splat shader ignores UV, so this costs every other scene
	# nothing; the W2 flat-colour terrain reads it to paint golf greens the
	# brightest green and build pads their own earth, which the four splat weights
	# alone cannot distinguish (a groomed fairway and flat rough are both
	# grass = 1). See the write site for why the crater rides the same float.
	var guv := PackedVector2Array()
	# Second UV channel, same idea one step on: x = forest weight, y = path
	# grooming weight. Neither is derivable from the four splat weights (a wooded
	# hillside and open rough are both grass-dominant; a track and a build pad are
	# both soil), and both are things SCENE_test_zone_W2's terrain shader has to be
	# able to paint apart. The stock splat shader ignores UV2 entirely, so this
	# costs every other scene one unused Vector2 per vertex and nothing else.
	var guv2 := PackedVector2Array()
	gheight.resize(total)
	gnormal.resize(total)
	gcolor.resize(total)
	guv.resize(total)
	guv2.resize(total)

	for gj in range(r, g - r):
		var row := gj * g
		for gi in range(r, g - r):
			var k := row + gi
			var h := gbase[k]
			var wx := gx[gi]
			var wz := gz[gj]
			var hx0: float
			var hx1: float
			var hz0: float
			var hz1: float
			if probe:
				var rs := ruin if ruins.is_empty() else _ruin_at_point(ruin, ruins, wx, wz)
				hx0 = _height_at(field, isl, wx - d, wz, zones, zi, rs)
				hx1 = _height_at(field, isl, wx + d, wz, zones, zi, rs)
				hz0 = _height_at(field, isl, wx, wz - d, zones, zi, rs)
				hz1 = _height_at(field, isl, wx, wz + d, zones, zi, rs)
			else:
				hx0 = gbase[k - r]
				hx1 = gbase[k + r]
				hz0 = gbase[k - r * g]
				hz1 = gbase[k + r * g]

			var nrm := Vector3((hx0 - hx1) / (2.0 * d), 1.0, (hz0 - hz1) / (2.0 * d)).normalized()
			var slope := clampf(1.0 - nrm.y, 0.0, 1.0)
			var conv := IslandField.curvature(h, hx0, hx1, hz0, hz1, d)
			var m := gmask[k]
			var flat := gflat[k]
			var kind := gkind[k]
			var sand := field.sand_at(wx, wz, m, slope, flat, kind, gend[k])
			var forest := field.forest_at(wx, wz, m, slope, flat)
			# All three products of one radial evaluation: `x` is the height
			# offset in metres, `y` the 0..1 char weight, `z` the molten core.
			# See `IslandField.crater_at`.
			# `h` goes in so the bowl can pin its floor to a single datum rather
			# than letting the hillside under the crash site through it.
			var cr := field.crater_at(wx, wz, m, crater, h)
			# The pod's dent, on the same contract: `x` the height offset in
			# metres, `y` the 0..1 torn weight. `z` is unused and stays zero --
			# see `IslandField.divot_at` for why it is a Vector3 anyway.
			var dv := field.divot_at(wx, wz, m, divot, h) if divot != null \
					else Vector3.ZERO

			gheight[k] = field.surface_height(h, sand, cr.x, dv.x)

			# THE SHADING NORMAL IS NOT THE LANDFORM NORMAL where a bunker is.
			#
			# `nrm` comes off the PRE-SAND surface and stays the one the splat
			# classifies from, so a trap can never repaint its own walls as scree
			# and the splat is exactly as LOD-stable as it was. But the mesh that
			# is drawn is the dished one, and shading it with `nrm` lights a bowl
			# as though the ground were flat. That was invisible while traps were
			# 0.6 m deep and is not at 2.4 m -- geometry you can plainly see, lit
			# as though it were not there.
			#
			# Only derived where a trap can exist at all: `surface_height` is the
			# identity at sand = 0, so everywhere else the two normals are the same
			# expression and the four extra noise fetches would buy nothing. Every
			# term is a pure function of this vertex and its neighbours, so two
			# chunks sharing a vertex still compute it bit-identically.
			#
			# Skipped on the probe path (coarse LOD, vertex spacing past
			# `curvature_radius`): there the grid is wider than a trap is, so the
			# dish is a sub-vertex feature and there is no bowl to shade.
			#
			# THE CRATER DOES NOT TAKE THE PROBE EXEMPTION, and that is the only
			# difference between the two features here. A bunker is 13 m across
			# and has dropped below the vertex grid by the time the probe path
			# runs; the crash site is 62 m across the short axis and ~90 down the
			# long one, so it is still fifteen vertices wide at the 8 m rungs and
			# a bowl you can plainly see would be lit as flat ground for as long
			# as it stayed in view -- which, sitting on the coastline, is from
			# every approach to the island.
			var shade_n := nrm
			var kx0 := k - r
			var kx1 := k + r
			var kz0 := k - r * g
			var kz1 := k + r * g
			# The centre's `slope` is reused for every neighbour's trap
			# suppression -- see `IslandField._sand_surface` for why that is
			# both cheap and exactly what keeps this chunk-consistent.
			var do_sand := not probe and field.sand_enabled \
					and (field.sand_possible(flat, kind)
						or field.sand_possible(gflat[kx0], gkind[kx0])
						or field.sand_possible(gflat[kx1], gkind[kx1])
						or field.sand_possible(gflat[kz0], gkind[kz0])
						or field.sand_possible(gflat[kz1], gkind[kz1]))
			var do_crater := field.crater_near(wx, wz, crater, d)
			# THE DIVOT DOES NOT TAKE THE PROBE EXEMPTION EITHER, and unlike the
			# crater it is a close call worth stating. A bunker is a sub-vertex
			# feature by the time the probe path runs and is skipped; the crater
			# is ~90 m long and plainly is not. The dent is 20 m -- two vertices
			# wide at the 8 m rungs, which is exactly the size where "too small
			# to bother" is tempting and wrong: the pod is standing in it, the
			# player walks up to the pod, and the rung a 20 m feature is meshed
			# at when you are close enough to see the pod is the finest one. Lit
			# flat, its bank is a 2.9 m face with no shading on it at the one
			# range it is ever looked at from.
			var do_divot := divot != null and field.divot_near(wx, wz, divot, d)
			if do_sand or do_crater or do_divot:
				var sx0 := _feature_height(field, hx0, gx[gi - r], wz, gmask[kx0],
						slope, gflat[kx0], gkind[kx0], gend[kx0], crater, divot, do_sand)
				var sx1 := _feature_height(field, hx1, gx[gi + r], wz, gmask[kx1],
						slope, gflat[kx1], gkind[kx1], gend[kx1], crater, divot, do_sand)
				var sz0 := _feature_height(field, hz0, wx, gz[gj - r], gmask[kz0],
						slope, gflat[kz0], gkind[kz0], gend[kz0], crater, divot, do_sand)
				var sz1 := _feature_height(field, hz1, wx, gz[gj + r], gmask[kz1],
						slope, gflat[kz1], gkind[kz1], gend[kz1], crater, divot, do_sand)
				shade_n = Vector3((sx0 - sx1) / (2.0 * d), 1.0,
						(sz0 - sz1) / (2.0 * d)).normalized()
			gnormal[k] = shade_n
			# The WEAR, not the levelling weight — see `IslandField.ruin_wear`. The
			# levelling is already in `gbase`; this is only what the ground looks like.
			var rw := 0.0
			if not gruin.is_empty():
				rw = field.ruin_wear(wx, wz, gruin[k])
			gcolor[k] = field.splat_weights(slope, conv, sand, m, flat, kind, forest,
					cr.y, dv.y, rw)
			# The golf channel is the REMAPPED flatten weight, not the weight: the
			# ground eases out over a 75 m apron and the mowing does not. See
			# `IslandField.golf_groom_lo`. The build channel is unremapped — a pad
			# is cleared earth all the way out, which is what its apron already is.
			#
			# BOTH UV FLOATS CARRY TWO THINGS, TOLD APART BY SIGN: grooming
			# upward, crash site downward. UV.y is build grooming against crater
			# char, UV.x is golf grooming against the crater's molten core. Every
			# consumer clamps its own side (`clamp(UV.y, 0, 1)` for build,
			# `clamp(-UV.y, 0, 1)` for char, and the same pair on x), so each is
			# invisible to the other and to every shader that only knows about
			# one of them -- `terrain_flatcolor` reads a crater as no build pad
			# and no fairway, which is exactly what it should draw.
			#
			# A fifth channel would have meant ARRAY_CUSTOM0: a format flag, a
			# byte layout, and a sixth parallel array threaded through the
			# coastline clip, the skirt and the rim padding. The sign of a float
			# that is already carried through all four costs nothing and reaches
			# all four for free.
			#
			# EACH PAIR IS MUTUALLY EXCLUSIVE BY PLACEMENT, not by luck --
			# `crater_zone_max` keeps a crash site off the zones -- so the
			# branches below are only ever taken where the ash apron has drifted
			# over a pad's outer bank. The crater wins there, matching the order
			# `splat_weights` applies the two in. Writing `build - burn` instead
			# would have let them CANCEL, and a vertex reading zero for both is
			# the one answer that is wrong twice.
			#
			# ON X THE OVERLAP IS RARER STILL and the crater's claim stronger: the
			# molten core lives inside `crater_molten` of the radius, so a
			# collision needs a fairway running through the bottom of the bowl,
			# and a fairway there is not mown, it is slag.
			#
			# THE REMAP, NOT THE RAW WEIGHT, on y. `cr.y` is a radial coordinate
			# and `splat_weights` above wants it as one, to place its levels on;
			# what the shader wants is how burnt the ground looks, which
			# saturates well inside the rim. Doing it here means the shader is
			# handed the answer and needs no copy of `crater_char_full` that
			# could fall out of step with the field's. `cr.z` needs no equivalent
			# -- it is already the answer to the only question anyone asks of it.
			var build := flat if kind == IslandField.ZONE_BUILD else 0.0
			var burn := field.crater_burn(cr.y)
			var golf := field.golf_groom(flat) if kind == IslandField.ZONE_GOLF else 0.0
			guv[k] = Vector2(
					-cr.z if cr.z > 0.0 else golf,
					-burn if burn > 0.0 else build)
			# UV2 CARRIES ITS OWN SIGNED PAIR, on exactly the argument the UV
			# floats above make and with the same clamps on the far side:
			# forest litter upward, the pod's torn ground downward. The shader
			# reads `clamp(UV2.x, 0, 1)` for the needle floor and
			# `clamp(-UV2.x, 0, 1)` for the scuff, so each is invisible to the
			# other and to any shader that knows about only one.
			#
			# THE OVERLAP IS REAL HERE, unlike the crater's pairings, and the
			# divot wins it on purpose. A dent is placed on wild ground, and wild
			# ground on this island is usually WOOD -- so the two genuinely do
			# coincide and one of them has to lose the channel. Needle floor
			# under a pod that ploughed the topsoil off is the wrong answer;
			# torn earth is the right one, and it is also the more recent event,
			# which is the same tie-break `splat_weights` applies between the
			# crash site and the grooming.
			#
			# THE REMAP, NOT THE RAW WEIGHT, for the reason `burn` above is: the
			# radial coordinate is what `splat_weights` places its levels on,
			# and what a shader wants is how torn the ground LOOKS. Doing it
			# here means the shader needs no copy of `divot_scuff_full`.
			# TAKEN ONLY WHEN THERE IS SOMETHING TO SHOW, which is the one place
			# this pairing needs a threshold and the crater's does not. The
			# crater's two claimants are rare by placement — `crater_zone_max`
			# keeps a crash site off the pads — so `> 0.0` is very nearly never
			# evaluated on a vertex that has anything to lose. The divot's
			# overlap is GUARANTEED: a dent is placed on wild ground, wild ground
			# here is wood, and `divot_scuff` is a smoothstep that is positive
			# everywhere inside the footprint. At `> 0.0` the outermost ring of
			# the dent — where the scuff is a thousandth and draws nothing —
			# would zero the needle floor for it, and what that paints is a bare
			# annulus of grass around the dent with the forest resuming outside
			# it. Below `_SCUFF_MIN` the scuff is not visible and the litter is,
			# so the litter keeps the channel.
			# Guarded on the weight rather than on `divot`, because the remap is
			# only interesting where there is one — `divot_scuff(0)` is 0.
			var scuff := field.divot_scuff(dv.y) if dv.y > 0.0 else 0.0
			guv2[k] = Vector2(
					-scuff if scuff > _SCUFF_MIN else forest,
					flat if kind == IslandField.ZONE_PATH else 0.0)

	# ------------------------------------------------------------ contouring

	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var idx := PackedInt32Array()

	# Coastline segments, flattened as [ax, az, bx, bz, ...] in LOGICAL space
	# (not pivot-relative — the cliff sweep needs to query the field with them).
	var coast := PackedFloat64Array()

	# Splat for a vertex sitting exactly on the coastline. Asking the field for
	# the mask = 0 case rather than hardcoding it keeps this in step with however
	# `coast_rock_width` is tuned, so the lip never disagrees with the ground one
	# cell inland.
	var coast_splat := field.splat_weights(0.0, 0.0, 0.0, 0.0)

	# Scratch reused per cell: polygon position / normal / colour, the logical XZ
	# of each vertex, and whether it came from a crossing rather than a corner.
	var poly_p: Array[Vector3] = []
	var poly_n: Array[Vector3] = []
	var poly_c: Array[Color] = []
	var poly_uv: Array[Vector2] = []
	var poly_uv2: Array[Vector2] = []
	var poly_w: Array[Vector2] = []
	var poly_x: Array[bool] = []

	for lj in range(n):
		for li in range(n):
			# The four corners of this cell, walked in rotational order. +X right
			# and +Z "down" viewed from above makes this clockwise from above,
			# which is Godot's front-facing winding — though `_push_tri` enforces
			# the winding anyway, so this only needs to keep the polygon simple.
			var k00 := (lj + r) * g + (li + r)
			var corners := [k00, k00 + 1, k00 + 1 + g, k00 + g]

			poly_p.clear()
			poly_n.clear()
			poly_c.clear()
			poly_uv.clear()
			poly_uv2.clear()
			poly_w.clear()
			poly_x.clear()

			for e in range(4):
				var ka: int = corners[e]
				var kb: int = corners[(e + 1) % 4]
				var ma := gmask[ka]
				var mb := gmask[kb]
				if ma > 0.0:
					var ax := gx[ka % g]
					var az := gz[ka / g]
					poly_p.append(Vector3(ax - pivot.x, gheight[ka] - pivot.y, az - pivot.z))
					poly_n.append(gnormal[ka])
					poly_c.append(gcolor[ka])
					poly_uv.append(guv[ka])
					poly_uv2.append(guv2[ka])
					poly_w.append(Vector2(ax, az))
					poly_x.append(false)
				if (ma > 0.0) != (mb > 0.0):
					var cw := _crossing(ka, kb, gmask, g, gx, gz)
					poly_p.append(Vector3(cw.x - pivot.x, isl.base_y - pivot.y,
							cw.y - pivot.z))
					# The shore ramp is flat where it meets the cliff, so the
					# coastline vertex is level and its lip is bare rock.
					#
					# LEVEL AND UPWARD-FACING IS ALSO WHAT KEEPS THE RIM A CREASE.
					# The plateau and the cliff are separate meshes with separate
					# materials, so no normal is ever averaged across the join: the
					# top's last vertex looks straight up and the cliff's first ring
					# looks out and down. Smooth-shading both (see
					# `SHADER_terrain_flatcolor.gdshader`'s `flat_shading`) therefore
					# smooths each surface and leaves the edge between them hard,
					# which is exactly the brief.
					poly_n.append(Vector3.UP)
					poly_c.append(coast_splat)
					poly_uv.append(Vector2.ZERO)
					poly_uv2.append(Vector2.ZERO)
					poly_w.append(cw)
					poly_x.append(true)

			var count := poly_p.size()
			if count < 3:
				continue

			# Fan the polygon. Clipping a convex cell against one half-plane keeps
			# it convex — the saddle case just cuts two opposite corners off the
			# square — so a fan from vertex 0 is always valid.
			var base := verts.size()
			for i in range(count):
				verts.append(poly_p[i])
				norms.append(poly_n[i])
				cols.append(poly_c[i])
				uvs.append(poly_uv[i])
				uv2s.append(poly_uv2[i])
			for i in range(1, count - 1):
				_push_tri(idx, verts, base + 0, base + i, base + i + 1, Vector3.UP)

			# Any two ADJACENT crossing points bound a stretch of coastline. A
			# saddle contributes two such pairs, every other case exactly one.
			if want_cliffs:
				for i in range(count):
					var j := (i + 1) % count
					if poly_x[i] and poly_x[j]:
						coast.append(poly_w[i].x)
						coast.append(poly_w[i].y)
						coast.append(poly_w[j].x)
						coast.append(poly_w[j].y)

	if verts.is_empty():
		return {}

	if field.chunk_skirt_depth > 0.0:
		_build_skirt(field, n, r, g, gx, gz, gmask, gheight, gcolor, guv, guv2,
				pivot, verts, norms, cols, uvs, uv2s, idx)

	# THE RIM IS BUILT BEFORE THE SURFACE IS FINALISED, because half of it lands
	# IN the surface: `_build_rim` appends the shoulder to these very arrays so
	# the lip is drawn by the terrain material. The wall comes back separately, as
	# a list of vertically stacked bands.
	var bands: Array = []
	var aabb_cliff := AABB()
	if want_cliffs and not coast.is_empty():
		bands = _build_rim(field, isl, coast, pivot, coast_splat,
				verts, norms, cols, uvs, uv2s, idx)
		for i in range(bands.size()):
			var bb: AABB = bands[i]["aabb"]
			aabb_cliff = bb if i == 0 else aabb_cliff.merge(bb)

	var top := _surface(verts, norms, cols, uvs, uv2s, idx)
	# Reported SEPARATELY from the wall's, and that matters for culling.
	#
	# Every wall column sweeps from its coastline point to a tip on the island's
	# centre axis hundreds of metres down, so a rim chunk's wall bounds span all
	# the way to the island centre — on the hub that measured 1556 m across and
	# 629 m tall, about 169 times the volume of the chunk's own footprint. Merging
	# that into one AABB with the top surface handed the walkable ground the
	# wall's bounds too, and a rim chunk then stayed "visible" from almost
	# anywhere. Kept apart, the top surface culls on its own honest footprint —
	# which the shoulder now extends a few tens of metres downward, against the
	# wall's hundreds, so that argument still holds with room to spare.
	var aabb_top := _bounds(verts)
	var aabb := aabb_top
	if not bands.is_empty():
		aabb = aabb.merge(aabb_cliff)

	return {"top": top, "cliff_bands": bands, "aabb": aabb,
			"aabb_top": aabb_top, "aabb_cliff": aabb_cliff}


# Final surface height at one grid NEIGHBOUR — the base height with the crash
# crater and the pod's divot stamped in and, where this chunk is deriving one,
# the bunker dish. This is what the shading normal above is differentiated from.
#
# `do_sand` is passed rather than re-derived so the four calls agree with each
# other and with the gate that decided to make them; `slope` is the CENTRE
# point's landform slope reused for all four, which is what
# `IslandField._sand_surface` does and for the reason its comment gives.
static func _feature_height(field: IslandField, base_h: float, x: float, z: float,
		mask: float, slope: float, flat: float, kind: int, end_d: float,
		crater: IslandField.Crater, divot: IslandField.Divot,
		do_sand: bool) -> float:
	var sand := field.sand_at(x, z, mask, slope, flat, kind, end_d) if do_sand else 0.0
	return field.surface_height(base_h, sand,
			field.crater_at(x, z, mask, crater, base_h).x,
			field.divot_at(x, z, mask, divot, base_h).x)


# Pre-sand terrain height at an arbitrary point — the off-grid neighbour lookup
# the coarse-LOD curvature probe needs.
#
# The zone influence has to be evaluated here too. Reading these neighbours off
# the un-flattened surface would hand every vertex inside a fairway the slope and
# curvature of the hill the fairway replaced, so the splat would paint a groomed
# green as rocky scree and the shading would light it as though it still bulged.
#
# The ruin's clearing likewise, and for the same reason: it is levelled into
# `gbase` for the grid path, so the probe path has to level it into its
# neighbours or a distant clearing would be shaded as the hill it replaced.
static func _height_at(field: IslandField, isl: IslandField.Island,
		x: float, z: float, zones: Array, zi: Array,
		ruin: IslandField.RuinSite = null) -> float:
	# `zi` is the caller's size-5 scratch array, so the height weight comes back in
	# slot 4 rather than as the return value. See `IslandField.zone_at`.
	field.zone_at(x, z, zones, zi)
	var m := field.mask_for(isl, x, z)
	var h := field.base_height(x, z, m, isl, zi[4], zi[1])
	if ruin != null:
		h += field.ruin_at(x, z, m, ruin, h).x
	return h


# The ruin clearing a vertex is levelled by: the chunk's one hoisted clearing, or —
# on the chunk wide enough to reach two, where `ruins` holds them — the nearer of
# them, which is the only one that can reach the vertex (`IslandField.ruin_near`).
static func _ruin_at_point(ruin: IslandField.RuinSite, ruins: Array, x: float,
		z: float) -> IslandField.RuinSite:
	if ruins.is_empty():
		return ruin
	var p := Vector2(x, z)
	var best: IslandField.RuinSite = null
	var best_d2 := INF
	for s in ruins:
		var site: IslandField.RuinSite = s
		var d2 := site.center.distance_squared_to(p)
		if d2 < best_d2:
			best_d2 = d2
			best = site
	return best


# ---------------------------------------------------------------------- skirt

# Hang a vertical apron off the chunk's four boundary edges.
#
# This is what lets neighbouring chunks run at different LODs. They agree exactly
# on the grid points they share — the LOD grids nest, since halving the cell
# count doubles the step — but the finer chunk has extra vertices in between that
# follow the terrain while the coarser chunk cuts straight across, so the two
# surfaces part company by a little. The skirt covers that gap from whichever
# side is higher.
#
# Only emitted where both ends of a boundary edge are land. Where the coastline
# crosses a boundary the contour, not the skirt, is responsible — which is why
# `SCRIPT_island_world.gd` pins every chunk holding coastline to one shared LOD.
static func _build_skirt(field: IslandField, n: int, r: int, g: int,
		gx: PackedFloat64Array, gz: PackedFloat64Array, gmask: PackedFloat32Array,
		gheight: PackedFloat32Array, gcolor: PackedColorArray, guv: PackedVector2Array,
		guv2: PackedVector2Array, pivot: Vector3, verts: PackedVector3Array,
		norms: PackedVector3Array, cols: PackedColorArray, uvs: PackedVector2Array,
		uv2s: PackedVector2Array, idx: PackedInt32Array) -> void:
	var drop := field.chunk_skirt_depth
	# The four borders as (start index, step, outward direction). Indices run
	# along each border in grid-index space.
	var borders := [
		[r * g + r, 1, Vector3(0.0, 0.0, -1.0)],            # min Z
		[(r + n) * g + r, 1, Vector3(0.0, 0.0, 1.0)],       # max Z
		[r * g + r, g, Vector3(-1.0, 0.0, 0.0)],            # min X
		[r * g + r + n, g, Vector3(1.0, 0.0, 0.0)],         # max X
	]
	for b in borders:
		var start: int = b[0]
		var stride: int = b[1]
		var outward: Vector3 = b[2]
		for s in range(n):
			var ka: int = start + s * stride
			var kb: int = ka + stride
			if gmask[ka] <= 0.0 or gmask[kb] <= 0.0:
				continue
			var pa := Vector3(gx[ka % g] - pivot.x, gheight[ka] - pivot.y, gz[ka / g] - pivot.z)
			var pb := Vector3(gx[kb % g] - pivot.x, gheight[kb] - pivot.y, gz[kb / g] - pivot.z)
			var base := verts.size()
			verts.append(pa)
			verts.append(pb)
			verts.append(pb - Vector3(0.0, drop, 0.0))
			verts.append(pa - Vector3(0.0, drop, 0.0))
			for i in range(4):
				norms.append(outward)
			# Match the ground it hangs from, so a skirt that does peek through
			# reads as more terrain rather than a stripe of the wrong material.
			cols.append(gcolor[ka])
			cols.append(gcolor[kb])
			cols.append(gcolor[kb])
			cols.append(gcolor[ka])
			uvs.append(guv[ka])
			uvs.append(guv[kb])
			uvs.append(guv[kb])
			uvs.append(guv[ka])
			uv2s.append(guv2[ka])
			uv2s.append(guv2[kb])
			uv2s.append(guv2[kb])
			uv2s.append(guv2[ka])
			_push_quad(idx, verts, base, base + 1, base + 2, base + 3, outward)


# ------------------------------------------------------------------------ rim

# Sweep every coastline segment from the shore down to the island's tip.
#
# ONE PROFILE, TWO SURFACES. Each column is a single continuous curve — a
# shoulder that rounds off the rim, then a wall that plunges under it — but the
# two halves are emitted into different meshes, because they are different jobs:
#
#   * THE SHOULDER goes into the WALKABLE SURFACE's arrays, with splat weights,
#     UVs and all. So it is drawn by the terrain material, which means the rock
#     on the lip is the same shader sampling the same texture at the same world
#     coordinates as the rock band on the shore above it — continuous by
#     construction rather than by two materials being tuned to match. It is also
#     why the shoulder carries a `coast_splat` colour rather than a hardcoded
#     rock: ask the field, and the lip can never disagree with the ground.
#
#   * THE WALL goes into BANDS, each its own surface and its own mesh. See
#     `_wall_bands`.
#
# The two share the ring at the handoff — index `sr` of the profile is both the
# shoulder's last ring and the wall's first, emitted into both meshes from the
# same computed value. Sharing the VALUE rather than recomputing it is what makes
# a crack there impossible, and taking both copies' normals from the same
# following segment is what stops it shading as a seam.
#
# The whole thing stays a pure function of the coastline point's XZ, which is
# what keeps it watertight sideways too: two adjacent segments share an endpoint
# exactly, so they generate an identical column of vertices there.
static func _build_rim(field: IslandField, isl: IslandField.Island,
		coast: PackedFloat64Array, pivot: Vector3, coast_splat: Color,
		tverts: PackedVector3Array, tnorms: PackedVector3Array,
		tcols: PackedColorArray, tuvs: PackedVector2Array,
		tuv2s: PackedVector2Array, tidx: PackedInt32Array) -> Array:
	var wr := field.cliff_wall_rings_for(isl)      # wall rings after the handoff
	var sh := field.cliff_shoulder_for(isl)        # (depth scale, inset, height)
	var sr := maxi(field.cliff_shoulder_rings, 1) if sh.z > 0.0 else 0

	# How far this island's underside actually descends, and where along its
	# nominal cone that lands. `t_end` is 1 for a small island whose cone fits
	# above the cutoff, and much less for the hub, whose wall is sliced off at the
	# fog floor long before it would taper — which is exactly why the hub reads as
	# a sheer cliff and a satellite reads as a terraced spike.
	var depth := field.cliff_depth_for(isl)
	var drop_max := field.cliff_drop_for(isl)
	var t_end := 1.0
	if drop_max < depth:
		t_end = pow(clampf(drop_max / depth, 0.0, 1.0), 1.0 / field.cliff_ring_bias)

	# Where along the cone the shoulder hands over. Clamped to half the built drop
	# so a shallow island — one whose whole underside is shorter than the lip
	# wants to be — degrades to a smaller lip instead of a shoulder with no wall
	# under it and an inverted ring range.
	var t_s := 0.0
	if sr > 0:
		var want := minf(sh.z, drop_max * 0.5)
		t_s = pow(clampf(want / depth, 0.0, 1.0), 1.0 / field.cliff_ring_bias)

	var bands := _wall_bands(field, wr)
	var acc: Array = []
	for _b in bands:
		acc.append({"v": PackedVector3Array(), "n": PackedVector3Array(),
				"c": PackedColorArray(), "i": PackedInt32Array(), "cols": {}})

	# The tip: one vertex shared by every column, on the island's centre axis. It
	# belongs to the LAST band, which is the only one that closes onto it.
	var last: Dictionary = acc[acc.size() - 1]
	var tip_i := (last["v"] as PackedVector3Array).size()
	(last["v"] as PackedVector3Array).append(Vector3(isl.center.x - pivot.x,
			isl.base_y - drop_max - pivot.y, isl.center.y - pivot.z))
	(last["n"] as PackedVector3Array).append(Vector3.DOWN)
	(last["c"] as PackedColorArray).append(Color(0.0, 0.0, 1.0, 0.0))

	# Coastline segments meet end to end, so neighbouring segments ask for the
	# same column twice. Sharing it isn't just a vertex saving: duplicate columns
	# would each accumulate normals from only half the surrounding faces, putting
	# a shading seam down the wall at every segment join.
	var shoulder_cols := {}
	var profiles := {}
	var outs := {}

	var seg_count := coast.size() / 4
	for s in range(seg_count):
		var ax := coast[s * 4 + 0]
		var az := coast[s * 4 + 1]
		var bx := coast[s * 4 + 2]
		var bz := coast[s * 4 + 3]

		var pa := _rim_profile(field, isl, ax, az, sr, wr, depth, t_s, t_end, sh,
				drop_max, profiles)
		var pb := _rim_profile(field, isl, bx, bz, sr, wr, depth, t_s, t_end, sh,
				drop_max, profiles)

		# Outward is away from the island axis. Well defined for the whole profile,
		# though for two different reasons: the shoulder moves steadily OUTWARD as
		# it drops (a fillet flares — see `_rim_profile`) and the wall moves
		# steadily inward. The widest ring is the handoff between them, so nothing
		# above it is hidden under anything, and the sweep never self-intersects.
		var mid := Vector2((ax + bx) * 0.5, (az + bz) * 0.5) - isl.center
		var outward := Vector3(mid.x, 0.0, mid.y)
		if outward.length_squared() < 1e-9:
			outward = Vector3.FORWARD
		outward = outward.normalized()

		# --- the shoulder, into the walkable surface --------------------------
		if sr > 0:
			var ia := _emit_column(pa, 0, sr, ax, az, isl, pivot, shoulder_cols,
					tverts, tnorms, tcols, coast_splat, field, outs)
			var ib := _emit_column(pb, 0, sr, bx, bz, isl, pivot, shoulder_cols,
					tverts, tnorms, tcols, coast_splat, field, outs)
			# The surface arrays carry two more attributes than the wall's do, and
			# the shoulder has nothing to say in either: it is off the edge of the
			# island, so no zone grooming (UV) and no forest (UV2) reach it. Zero
			# is also exactly what the coastline vertex above it already carries.
			while tuvs.size() < tverts.size():
				tuvs.append(Vector2.ZERO)
				tuv2s.append(Vector2.ZERO)
			for k in range(sr):
				_push_quad(tidx, tverts, ia + k, ib + k, ib + k + 1, ia + k + 1,
						outward)

		# --- the wall, into its bands -----------------------------------------
		for bi in range(bands.size()):
			var lo: int = bands[bi][0]
			var hi: int = bands[bi][1]
			var a: Dictionary = acc[bi]
			var ja := _emit_column(pa, sr + lo, hi - lo, ax, az, isl, pivot,
					a["cols"], a["v"], a["n"], a["c"], Color(0.0, 0.0, 1.0, 0.0),
					field, outs)
			var jb := _emit_column(pb, sr + lo, hi - lo, bx, bz, isl, pivot,
					a["cols"], a["v"], a["n"], a["c"], Color(0.0, 0.0, 1.0, 0.0),
					field, outs)
			for k in range(hi - lo):
				_push_quad(a["i"], a["v"], ja + k, jb + k, jb + k + 1, ja + k + 1,
						outward)
			if bi == bands.size() - 1:
				# Close the last ring onto the shared tip.
				_push_tri(a["i"], a["v"], ja + (hi - lo), jb + (hi - lo), tip_i,
						outward)

	var out: Array = []
	for a in acc:
		var v: PackedVector3Array = a["v"]
		var i: PackedInt32Array = a["i"]
		if i.is_empty():
			continue
		out.append({
			"arrays": _surface(v, a["n"], a["c"], PackedVector2Array(),
					PackedVector2Array(), i),
			"aabb": _bounds(v),
		})
	return out


# Ring ranges for the wall's bands, as [first, last] pairs into the profile —
# each band's LAST ring is the next band's FIRST, so the two emit the same
# vertices and the wall cannot crack between them.
#
# WHY THE WALL IS CUT UP AT ALL. One mesh from the rim to the tip has an AABB
# that reaches from the coastline to the middle of the island and hundreds of
# metres down — measured at ~169x the volume of the chunk's own footprint on the
# hub. That box is useless to a frustum test: it is "visible" from almost
# anywhere, so the whole sweep is submitted whenever any part of the chunk is on
# screen, including the 500-odd metres of it that the material has already faded
# to nothing. Cut into bands, each one carries a box a few tens of metres tall
# and the ones below the fog fail the test on their own.
#
# EQUAL RING COUNTS, NOT EQUAL DEPTHS, because `cliff_ring_bias` has already
# bunched the rings toward the top: equal counts therefore give thin bands where
# the wall is close and visible and fat ones where it is deep and hazed, which is
# exactly the right way round for culling.
static func _wall_bands(field: IslandField, wr: int) -> Array:
	# At least two rings to a band. Below that the split stops paying for itself:
	# each band is a draw call per coastal chunk, and a band holding a single quad
	# ring buys a tighter box than the triangles in it are worth. `wr` is itself
	# adaptive (see `IslandField.cliff_wall_rings_for`), so this is what keeps a
	# near-vertical wall from being cut into more pieces than it has shape.
	var n := clampi(field.cliff_wall_bands, 1, maxi(wr / 2, 1))
	var out: Array = []
	var cut := 0
	for b in range(n):
		var nxt := int(round(float(wr) * float(b + 1) / float(n)))
		nxt = maxi(nxt, cut + 1)
		out.append([cut, mini(nxt, wr)])
		cut = nxt
		if cut >= wr:
			break
	return out


# Append rings `from .. from + count` of `prof` as a column of vertices, or hand
# back the index of the copy an earlier segment already made.
#
# Keyed on the exact logical coordinates: the two cells either side of a
# coastline edge produce bit-identical crossings (see `_crossing`), so equal keys
# really are the same point. The key carries the ring range too, because the
# same coastline point appears once per band and those copies live in different
# arrays.
static func _emit_column(prof: Array, from: int, count: int, x: float, z: float,
		isl: IslandField.Island, pivot: Vector3, cache: Dictionary,
		verts: PackedVector3Array, norms: PackedVector3Array,
		cols: PackedColorArray, splat: Color, field: IslandField,
		outs: Dictionary) -> int:
	var key := Vector3(x, z, float(from))
	if cache.has(key):
		return cache[key]
	var base := verts.size()
	var radial := Vector2(x, z) - isl.center
	var r0 := radial.length()
	var dir := radial / r0 if r0 > 1e-6 else Vector2(1.0, 0.0)
	# WHICH WAY THE COASTLINE FACES HERE, which is NOT `dir` — see `_coast_out`.
	var out := _coast_out(field, isl, x, z, dir, outs)
	# How much of a ring-to-ring radial step is a step along that facing. 1 where
	# the two agree, and it is what keeps the vertical term below honest: the
	# sweep advances by `dr` along `dir`, but the surface only tilts by the part
	# of that which lies in the plane the normal is turning in.
	var lean := dir.dot(out)
	for k in range(from, from + count + 1):
		var p: Vector2 = prof[k]
		verts.append(Vector3(isl.center.x + dir.x * p.x - pivot.x, p.y - pivot.y,
				isl.center.y + dir.y * p.x - pivot.z))
		# Normal straight from the profile slope rather than averaged from the
		# faces. Face averaging bands the wall visibly: marching squares produces
		# coastline segments of wildly uneven length, so area-weighted normals
		# come out uneven column to column. The profile is a smooth pure function
		# of position, so neighbouring columns agree and the wall shades cleanly.
		#
		# ALWAYS FROM THE FOLLOWING SEGMENT, including at a band boundary — which
		# is why `prof` runs one entry past every range this is ever asked for.
		# The shoulder's last ring and the wall's first are the same point and
		# take the same following segment, so they get the same normal and the
		# handoff shades as one surface across two meshes.
		#
		# (dr, dy) runs down-and-inward along the surface. The normal is the
		# cross product of that profile tangent with the COASTLINE tangent — the
		# other direction the surface runs in — which is `out` turned a quarter
		# turn in XZ. Writing that product out leaves the horizontal part pointing
		# along `out` and the vertical part scaled by `lean`, i.e. exactly the
		# formula this used to have with `dir` in place of `out`.
		var nxt: Vector2 = prof[k + 1]
		var dr := nxt.x - p.x
		var dy := nxt.y - p.y
		var n := Vector3(out.x * -dy, dr * lean, out.y * -dy)
		norms.append(n.normalized() if n.length_squared() > 1e-12 else Vector3.DOWN)
		cols.append(splat)
	cache[key] = base
	return base


# The OUTWARD direction of the coastline itself at (x, z), in XZ — the mask's own
# gradient, reversed, since the mask rises inland.
#
# WHY THIS IS NOT THE RADIAL DIRECTION, which is what the rim's normals used
# until now. The sweep is a surface of revolution in its PROFILE — every ring of
# a column sits on the same bearing from the island's centre axis — and it is
# tempting to read that as "the surface faces outward along the radius". Its
# CROSS-SECTION is not a circle. The coastline is the zero contour of
#
#     mask = 1 - d / radius + coast_wobble * coast_irregularity
#
# and it is the SECOND term that steers. The radial term's gradient is a
# constant 1/radius — 0.00080 per metre on the 1250 m hub, and always along the
# radius; the wobble's is 0.00128 per metre at the shore and points wherever the
# noise happens to be falling. At 1.6 to 1 in favour of the term that does not
# care about the radius, the contour is only loosely a circle, and the angle
# between the radius and the direction the shore actually faces is not a
# correction — it is most of the answer. `tests/PROBE_rim_normals.gd` measures
# both numbers on the shipped hub, and the deviation they produce: mean 48
# degrees, 59% of the shoreline past 45, worst 81.
#
# WHAT THAT COST, and why it showed up as a TEXTURE bug rather than a lighting
# one. `terrain_splat_w2` and `cliff_wall` are both triplanar with
# `triplanar_sharpness = 4`, so `pow(abs(n), 4)` picks the projection plane from
# this normal. Past 45 degrees the wrong axis wins, and the wrong axis on a
# cliff is one whose plane lies ALONG the wall rather than across it: world
# position barely moves within it as you travel round the island, so the rock
# smears into metre-long horizontal streaks. The lighting was wrong by the same
# angle at the same time, which is the second half of what made the perimeter
# read as a smeared band rather than as rock.
#
# A PURE FUNCTION OF POSITION, which is the property that matters here. The
# coastline point on a chunk boundary is generated by cells in BOTH chunks and
# each chunk only ever sees one of the two segments meeting there, so a tangent
# averaged from the segments to hand would differ across the join and put a
# shading seam down every chunk edge. The mask does not know about chunks.
static func _coast_out(field: IslandField, isl: IslandField.Island, x: float,
		z: float, dir: Vector2, cache: Dictionary) -> Vector2:
	var key := Vector2(x, z)
	if cache.has(key):
		return cache[key]
	var g := Vector2(
			field.mask_for(isl, x + COAST_NORMAL_EPS, z)
					- field.mask_for(isl, x - COAST_NORMAL_EPS, z),
			field.mask_for(isl, x, z + COAST_NORMAL_EPS)
					- field.mask_for(isl, x, z - COAST_NORMAL_EPS))
	var out := dir if g.length_squared() < 1e-18 else (-g).normalized()
	cache[key] = out
	return out


# The (radius, y) profile for the column under (x, z): `sr` shoulder rings, then
# `wr` wall rings, then ONE EXTRA entry so the last real ring still has a
# following segment to take its normal from.
#
# Cached per island build, because every coastline point is asked for once per
# band plus once for the shoulder and the answer is the same every time.
static func _rim_profile(field: IslandField, isl: IslandField.Island, x: float,
		z: float, sr: int, wr: int, depth: float, t_s: float, t_end: float,
		sh: Vector3, drop_max: float, cache: Dictionary) -> Array:
	var key := Vector2(x, z)
	if cache.has(key):
		return cache[key]

	var radial := Vector2(x, z) - isl.center
	var r0 := radial.length()
	# Per-position depth wobble so the underside isn't a perfect cone. Faded out
	# toward the tip so every column still lands on exactly the shared tip.
	var wobble := field.cliff_wobble(x, z)
	var prof: Array[Vector2] = []

	# --- the shoulder ---------------------------------------------------------
	#
	# IT FLARES OUTWARD, and getting that backwards is the one mistake here worth
	# writing down, because the first version compiled, tessellated, passed every
	# watertightness check and rendered a shape that was wrong in a way no
	# assertion caught.
	#
	# A surface that descends while moving INWARD is an UNDERCUT: its outer face
	# points down and out, so it sees no sun and is lit almost entirely by sky
	# ambient. Rendered, the "shoulder" came back blue — mean rgb (66, 54, 72)
	# against a rock texture whose own mean is warm — while the swept cone it
	# replaced measured (86, 83, 62). It was not a grading problem; the faces were
	# genuinely pointing at the ground.
	#
	# A fillet is the other way round. Round over the edge of a cylinder and the
	# arc runs from the top face DOWN AND OUT to meet the wall: radius grows with
	# depth, and the normal swings from straight up to straight out — which is what
	# makes a shoulder read as one. So the lip leaves the coastline and flares.
	#
	# The cost is that the island is `cliff_shoulder_inset` wider just below its
	# shore than at it, and the wall therefore stands a few metres proud of the
	# turf line. That is what a weathered cliff edge looks like anyway, and it is
	# the reason the coastline itself did not have to move — a true fillet on an
	# unchanged top face has to put its arc outside that face, because the only
	# alternative is pulling the walkable ground in, and every zone, scatter and
	# collider in the world is placed against where that ground currently ends.
	#
	# THE WOBBLE IS SPENT HERE, and that is a change worth stating. It used to be
	# applied to the wall's drop and faded out toward the tip, on the reasoning
	# that all of it should land in the part above the cloud deck. The shoulder
	# now IS that part, so the same noise instead varies how deep each column's
	# lip rolls over, and the wall simply starts wherever the lip finished. The
	# rim gets its irregularity, and — the reason this is not merely equivalent —
	# the handoff depth is then ONE number per column used by both halves, so the
	# two meshes meet exactly whatever the noise did.
	var d_s := 0.0
	if sr > 0:
		d_s = depth * pow(t_s, field.cliff_ring_bias) * (1.0 + wobble)
		d_s = clampf(d_s, 1.0, drop_max * 0.6)
		var l := d_s / IslandField.SHOULDER_SPANS
		for k in range(sr):
			var dd := d_s * float(k) / float(sr)
			prof.append(Vector2(r0 + sh.y * (1.0 - exp(-dd / l)),
					isl.base_y - dd))

	# The handoff, shared: the shoulder's last ring and the wall's first.
	var r_hand := r0 + sh.y * (1.0 - exp(-IslandField.SHOULDER_SPANS)) if sr > 0 else r0
	prof.append(Vector2(r_hand, isl.base_y - d_s))

	# --- the wall -------------------------------------------------------------
	#
	# Unchanged in shape from the bare cone this replaces, just started from the
	# shoulder's radius instead of the coastline's: `conv` lags `drop` by
	# `cliff_taper`, so the wall holds near-vertical under the plateau and only
	# closes up once it is deep in the fog.
	var t_lo := t_s
	for k in range(1, wr + 2):
		var t := lerpf(t_lo, t_end, float(k) / float(wr))
		var conv := _terraced(pow(t, field.cliff_taper), field.cliff_terraces)
		var drop := depth * pow(t, field.cliff_ring_bias)
		if k >= wr:
			# The last real ring and the extra normal-only entry both sit at the
			# cone's end, so every column reaches the SAME depth there and they
			# can share one tip vertex.
			conv = 1.0 if k > wr else conv
			drop = depth * pow(t_end, field.cliff_ring_bias)
		prof.append(Vector2(r_hand * (1.0 - conv), isl.base_y - drop))

	cache[key] = prof
	return prof


# A staircase from 0 to 1 in `steps` treads: flat through each tread, then a
# smooth riser. Gives ledges without the hard 90-degree corners that read as
# faceting once the normals are averaged. Never reaches 1 — the shared tip
# vertex is what finishes the convergence.
static func _terraced(t: float, steps: int) -> float:
	var band := t * float(steps)
	var tread := floorf(band)
	return (tread + smoothstep(0.35, 0.9, band - tread)) / float(steps)


# ---------------------------------------------------------------- primitives

# Logical XZ where the coastline crosses the edge between two grid points.
#
# Always interpolated from the lower grid index to the higher one, so the cell on
# either side of the edge computes bit-identical floats (precision rule 2). The
# height there is the island's base altitude: the shore ramp is zero at the
# coastline by construction, so that IS the exact surface height, and pinning it
# makes the cliff-top line dead level and trivially consistent between chunks.
static func _crossing(ka: int, kb: int, gmask: PackedFloat32Array, g: int,
		gx: PackedFloat64Array, gz: PackedFloat64Array) -> Vector2:
	var lo := mini(ka, kb)
	var hi := maxi(ka, kb)
	var ml := gmask[lo]
	var mh := gmask[hi]
	var t := ml / (ml - mh)
	var lx := gx[lo % g]
	var lz := gz[lo / g]
	return Vector2(lx + t * (gx[hi % g] - lx), lz + t * (gz[hi / g] - lz))


# Emit one triangle wound so that it is VISIBLE from `facing`.
#
# Godot's front face is clockwise, which means the right-hand cross product of a
# visible triangle points AWAY from the viewer — hence the `> 0.0` test rather
# than the `< 0.0` one you might expect. Same convention as
# `SCRIPT_procedural_island.gd`.
static func _push_tri(idx: PackedInt32Array, verts: PackedVector3Array,
		i0: int, i1: int, i2: int, facing: Vector3) -> void:
	var nrm := (verts[i1] - verts[i0]).cross(verts[i2] - verts[i0])
	if nrm.dot(facing) > 0.0:
		var t := i1
		i1 = i2
		i2 = t
	idx.append(i0)
	idx.append(i1)
	idx.append(i2)


static func _push_quad(idx: PackedInt32Array, verts: PackedVector3Array,
		i0: int, i1: int, i2: int, i3: int, facing: Vector3) -> void:
	_push_tri(idx, verts, i0, i1, i2, facing)
	_push_tri(idx, verts, i0, i2, i3, facing)


static func _surface(verts: PackedVector3Array, norms: PackedVector3Array,
		cols: PackedColorArray, uvs: PackedVector2Array, uv2s: PackedVector2Array,
		idx: PackedInt32Array) -> Array:
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = cols
	# Both UV channels are optional: only attached when the caller supplied one
	# vertex-for-vertex (the top surface does, the cliff does not). Attaching a
	# mismatched-length array would make add_surface_from_arrays reject the whole
	# surface.
	if uvs.size() == verts.size():
		arr[Mesh.ARRAY_TEX_UV] = uvs
	if uv2s.size() == verts.size():
		arr[Mesh.ARRAY_TEX_UV2] = uv2s
	arr[Mesh.ARRAY_INDEX] = idx
	return arr


static func _bounds(verts: PackedVector3Array) -> AABB:
	var lo := verts[0]
	var hi := verts[0]
	for v in verts:
		lo = lo.min(v)
		hi = hi.max(v)
	return AABB(lo, hi - lo)
