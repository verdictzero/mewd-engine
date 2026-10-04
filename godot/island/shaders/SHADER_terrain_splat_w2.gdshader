shader_type spatial;
render_mode cull_disabled, unshaded;
#include "res://godot/shaders/thermal_base.gdshaderinc"

#include "res://godot/island/shaders/SHADERINC_island_light.gdshaderinc"
#include "res://godot/island/shaders/SHADERINC_golf_wall.gdshaderinc"

// NINE-SURFACE textured terrain for SCENE_test_zone_W2, from the `textures/`
// photo set plus the two crater layers baked from it.
//
// It is the same data `SHADER_terrain_flatcolor.gdshader` reads -- the four splat
// weights in COLOR, plus the grooming channels in the two UV sets -- with each of
// them resolved to a TEXTURE instead of to a flat colour:
//
//   COLOR.r  grass   base rough turf        UV.x   golf    -> mown fairway
//   COLOR.g  soil    bare earth            -UV.x   molten  -> the pool at the core
//   COLOR.b  rock    cliff and scree        UV.y   build   -> (stays soil)
//   COLOR.a  sand    bunkers               -UV.y   crater  -> charred dirt / slag
//                                           UV2.x  forest  -> needle floor
//                                          -UV2.x  divot   -> torn earth / scarp
//                                           UV2.y  path    -> worn trail
//
// THREE OF THE FOUR UV FLOATS CARRY TWO OF THEM, told apart by sign -- the
// ordinary world positive, an impact site negative. See the `crater` and `divot`
// uniform blocks, and `SCRIPT_chunk_mesher.gd` for why a sign rather than extra
// vertex channels.
//
// WHY A THIRD TERRAIN SHADER rather than a fourth material on
// `SHADER_terrain_splat.gdshader`. That one is the textured terrain for
// SCENE_test_zone_W and knows nothing about the grooming channels: it has four
// layers, no UV inputs, and its own fog band (-200 .. -320) which the W scene's
// cloud decks and palette assertions are tuned against. W2's fog is a different
// band (-170 .. -320) with a single colour, and W2 needs all seven layers. Fusing
// them would mean one shader carrying two fog models and three dead texture
// samplers for whichever scene was not using them.
//
// THE VARIANT LAYERS BORROW THEIR BASE'S NORMAL MAP. Golf turf, forest floor and
// trail are mixed into the ALBEDO of the grass and soil channels and take those
// channels' normals. Seven independent normal maps would be seven more fetches
// for a difference nobody can see: the three variants are ground at the same
// relief scale as the layer they replace, and it is the albedo the eye reads.
// This shader is at SIXTEEN texture fetches on GL Compatibility over ordinary
// ground — fifteen for the splat, plus one for the environment ball the lighting
// include samples — and NINETEEN inside the crash crater, which is one island's
// worth of one island in the world and is branched off everywhere else.
//
// THE SAMPLER BUDGET IS SPENT. Fourteen are declared below and the lighting
// include declares `env_ball` and `env_ball_night`, which is SIXTEEN against the
// sixteen texture image units GLES3 guarantees and V3D provides exactly. There is
// no seventeenth. This note used to read "fifteen ... room for one more"; that was
// a true count before the night ball landed and it is not one now, so read the
// number here as a ceiling already reached rather than as headroom.
//
// That budget is why the crater layers borrow their normals and share the
// vegetation's ember ramp instead of baking their own: a charred normal map, a
// slag normal map and a second fire palette would each have been a sampler, and
// three would have been one too many. It is also why the strata overlay is
// COMPUTED — see the `strata` uniform block, which has the rest of that argument.
//
// PROJECTIONS. Rock is full triplanar because it has to cover vertical cliffs.
// Everything else is top (XZ) projection only, which halves the fetches -- those
// surfaces only ever appear on ground flat enough that the stretching is
// invisible, because the slope rule hands steep ground to rock. The strata
// overlay is the one projection that goes the other way: SIDE planes only, no top,
// which is what confines it to faces.
//
// NEAREST FILTERING, and the 128 px bakes it goes with. `scripts/SCRIPT_crunch_art.gd`
// crunches the 512 px source art down to 128 and quantises its colours; sampling
// that bilinearly would smear it straight back into the photograph it came from.
// Mipmaps stay ON -- a tiling ground texture at a grazing angle across a 2.5 km
// island is far below one texel per pixel long before the horizon, and without
// them the whole surface crawls.
//
// UNLIT, and the light is computed here rather than by the engine. See
// `SHADERINC_island_light.gdshaderinc` for the model and for why it is indexed by the WORLD
// normal instead of the view-space one a matcap would use. The short version: the
// cloud sea, the horizon band and the sky are all world-anchored, so terrain whose
// lighting swung with the camera would be the only thing in frame that did.
//
// WHAT `unshaded` TAKES WITH IT, deliberately in the first two cases:
//
//   * ROUGHNESS / METALLIC / SPECULAR. All three are dead under `unshaded`, and
//     none is a loss — every layer already wrote ROUGHNESS 1 and METALLIC 0
//     because a specular lobe on ground that is then snapped to one of sixteen
//     palette entries does not read as sheen, it reads as a patch of the wrong
//     colour sliding around as the camera moves.
//   * THE EMISSION DANCE ROUND THE FOG. A lit shader cannot fog by darkening
//     ALBEDO, because zeroing albedo does not make a fragment unlit; it had to
//     drain ALBEDO, put the haze in EMISSION and pull SPECULAR down with it. With
//     no light term there is nothing to survive, so the fog is a straight mix
//     toward `fog_color` — which is how `SHADER_veg_billboard.gdshader` has done it since
//     it went unlit, and the two now agree by construction rather than by having
//     been tuned to the same numbers.
//   * RECEIVED SHADOWS, which IS a real loss, and one with a wider consequence than
//     this surface. Nothing left in SCENE_test_zone_W2 receives a directional
//     shadow — the vegetation, the grass, the cloud sea and the horizon band are
//     all `unshaded` already, and this shader and `cliff_wall` were the last two
//     that were not — so the light's whole shadow pass now renders into a map
//     nothing reads. `directional_shadow_max_distance` and the atlas size are still
//     tuned as if it mattered.
//     They were already faint here — ambient 1.2 against a 1.0 sun, through a
//     sixteen-level LUT — and the banded sun term replaces what they were mostly
//     doing, which is telling you which way the ground faces. If they are wanted
//     back, the move is a custom `void light()` rather than reverting: it keeps
//     LIGHT_COLOR and the shadow term while still throwing away the PBR response.
//
// SMOOTH SHADING, and a hard rim. See `flat_shading` below; the short version is
// that the mesh normals `SCRIPT_chunk_mesher.gd` emits are analytic rather than averaged
// from faces, so interpolating them is smooth by construction, and the crease at
// the coastline survives because the cliff is a separate mesh with its own
// material.

// PER-LAYER GRADE. `*_tint` is a plain vec3, NOT `source_color`: it is a LINEAR
// per-channel multiplier on the sampled albedo, so it may legitimately exceed
// 1.0. Both halves of that are load-bearing rather than pedantic.
//
// A photo set is graded to nothing. This one spans an order of magnitude in level
// (dark_rock_02 averages 0.036 linear luminance, forest_ground_01 0.246), so left
// raw the rough blew out to cream under the scene's 3.0-energy sun while the rock
// crushed to black. And matching the level alone is still not enough: the rough
// averages olive-TAN, so at the right brightness and the wrong hue the island
// rendered as a khaki dune field. Hence three numbers per layer, not one.
//
// It matters more here than it would in most scenes because `post_dither` snaps
// every pixel to one of sixteen palette entries. A colour landing between two of
// them does not blend — it jumps to whichever is nearer — so an un-graded hue does
// not read as slightly off, it reads as a different surface.
//
// The shipped values land each layer's MEAN on the flat-colour palette entry it
// replaced, measured through this project's own import pipeline; the texture keeps
// all of its own variation and only its average moves. See
// MAT_terrain_splat_w2.tres for the measurements and the two exceptions.

group_uniforms grass;
// Wild rough. `forest_ground_01` -- moss and twigs, not a lawn.
uniform sampler2D grass_albedo : source_color, hint_default_white, filter_nearest_mipmap, repeat_enable;
uniform sampler2D grass_normal : hint_normal, filter_nearest_mipmap, repeat_enable;
uniform float grass_scale = 9.0;
uniform vec3 grass_tint = vec3(1.0);

group_uniforms golf;
// Mown fairway. `lawn_striped` -- the mower stripes are the point: they read as
// deliberate maintained ground from the air, which is exactly what a golf zone is.
uniform sampler2D golf_albedo : source_color, hint_default_white, filter_nearest_mipmap, repeat_enable;
uniform float golf_scale = 11.0;
uniform vec3 golf_tint = vec3(1.0);

group_uniforms soil;
// Cleared earth -- the build-pad surface, and the base the trail and the forest
// floor are mixed over. `dirt_01`.
uniform sampler2D soil_albedo : source_color, hint_default_white, filter_nearest_mipmap, repeat_enable;
uniform sampler2D soil_normal : hint_normal, filter_nearest_mipmap, repeat_enable;
uniform float soil_scale = 7.0;
uniform vec3 soil_tint = vec3(1.0);

group_uniforms forest;
// Needle litter under a canopy. `forest_ground_06`. Mixed into BOTH ground
// channels: `IslandField.forest_litter` has already moved part of the grass
// weight into soil, and the rest of the turf still wants to darken under the
// trees rather than stay open-meadow green.
uniform sampler2D forest_albedo : source_color, hint_default_white, filter_nearest_mipmap, repeat_enable;
uniform float forest_scale = 8.0;
uniform vec3 forest_tint = vec3(1.0);
// How far the grass channel darkens toward the floor under a full canopy. Under
// 1 because a wood is not bare -- there is still turf between the trees.
uniform float forest_grass_mix : hint_range(0.0, 1.0) = 0.75;

group_uniforms path;
// Worn track. `rocky_trail_02`.
uniform sampler2D path_albedo : source_color, hint_default_white, filter_nearest_mipmap, repeat_enable;
uniform float path_scale = 5.0;
uniform vec3 path_tint = vec3(1.0);
// MEWD — PAVED SQUARES, at the user's request for CANDY LAND: how far a
// build pad's ground is `build_albedo` instead of bare earth. 0 (every
// island before it) leaves the pads soil, as golf drew them.
uniform float build_paving : hint_range(0.0, 1.0) = 0.0;
uniform sampler2D build_albedo : source_color, hint_default_white, filter_nearest_mipmap, repeat_enable;
uniform float build_scale = 4.0;

group_uniforms steep_stone;
// THE STONE UP THE ISLAND'S SIDES (at the user's request, CANDY LAND: "the
// stone comes right up to where the slope on the edge of the island ends,
// then a fast change to grass"): wherever the ground is steeper than
// `steep_lo` (1 - normal.y) it is the cliff wall's own stone — the same
// texture, scale, tint, mean and contrast as SHADER_cliff_wall's rock, so
// the bulge over the lip and the wall under it are one face — whole by
// `steep_hi`, a narrow band, so it turns to grass sharply where the slope
// flattens out. Off (the default) while `steep_stone` is 0.
uniform float steep_stone = 0.0;
uniform float steep_lo = 0.30;
uniform float steep_hi = 0.36;
uniform sampler2D stone_albedo : source_color, hint_default_white, filter_nearest_mipmap, repeat_enable;
uniform float stone_scale = 8.0;
uniform vec3 stone_tint = vec3(1.0);
uniform vec3 stone_mean = vec3(1.0);
uniform float stone_contrast = 1.0;
// AND THE STONE FADES DOWN TO THE CLOUD SEA'S DARKEST GREY, after its light,
// from `deep_top` metres over the sea's surface to `deep_bottom` — the same
// band as SHADER_cliff_wall's `deep_*` (its `deep_bottom` is that shader's
// `sea_fade_above`), so the shoulder's stone and the wall under it fade as one
uniform bool deep_on = false;
uniform vec3 deep_color : source_color = vec3(0.4, 0.45, 0.52);
uniform float deep_top = 40.0;
uniform float deep_bottom = 14.0;
global uniform float sea_surface_y;

group_uniforms rock;
// `dark_rock_02` -- fractured slabs. Full triplanar; it is the only layer that
// has to cover a vertical face.
uniform sampler2D rock_albedo : source_color, hint_default_white, filter_nearest_mipmap, repeat_enable;
uniform sampler2D rock_normal : hint_normal, filter_nearest_mipmap, repeat_enable;
uniform float rock_scale = 12.0;
uniform vec3 rock_tint = vec3(1.0);
// The blend's commitment to one projection plane — and therefore the reason the
// MESH NORMAL is a texture input here and not only a lighting one. See the same
// uniform in `SHADER_cliff_wall.gdshader`, which carries the full note: past 45 degrees
// of normal error this picks a plane lying along the surface rather than across
// it, which is a smear rather than a shading mistake.
uniform float triplanar_sharpness : hint_range(1.0, 16.0) = 4.0;

group_uniforms strata;
// SEDIMENTARY BEDS ON THE CLIFF FACES, and nothing else in this shader works at
// this scale: every layer above is a SURFACE, tiled at metres, and this is a
// LANDFORM, banded at tens of metres. It modulates the rock channel rather than
// adding a channel of its own, so it costs no vertex colour and cannot change
// what the splat classifies.
//
// OFF BY DEFAULT (`strata_strength = 0`), which is what keeps W2's ground exactly
// as it was: the whole block is inside a branch on a UNIFORM, so a material that
// does not opt in pays one scalar compare per fragment and takes no other path.
// `MAT_terrain_splat_q.tres` opts in; `MAT_terrain_splat_w2.tres` does not.
//
// THREE THINGS DEFINE IT, and they are worth separating because only the first is
// obvious:
//
//   1. SIDE PROJECTION ONLY. The triplanar weights are already computed for rock;
//      this uses `bw.x + bw.z` and DROPS `bw.y` entirely. That is the whole of
//      "cliff faces only" and it costs no uniform of its own -- the falloff is
//      `triplanar_sharpness`, the dial that is already there. Keeping the top
//      plane would draw the band stack across every flat rock top in plan view,
//      which is corduroy and not geology. It also means the gate is GEOMETRIC:
//      a plateau rim gets strata and the plateau's own tabletop does not, from
//      one term, with nothing to keep in step.
//
//   2. WORLD Y, so the beds are GLOBAL. A bed sits at one altitude everywhere in
//      the world -- two mesas 3 km apart show the same bed at the same height,
//      which is the thing that reads as a shared geological history rather than
//      as decoration applied per landform. It is also what makes the overlay free
//      of chunk and LOD state: nothing here is per-chunk, so there is no seam to
//      get wrong.
//
//   3. NO DIP TERM, and that is a floating-origin constraint rather than taste.
//      Tilted beds would make band altitude a function of X and Z -- and X and Z
//      are exactly what `SCRIPT_floating_origin.gd` rebases (Q sets
//      `horizontal_only`, so world Y here is absolute forever and the bands never
//      move). A dip would make every band in the world jump at every rebase.
//      `strata_waver` below is the same hazard bounded: it re-phases at a rebase
//      by at most its own metres, which is the re-phasing every tiling ground
//      texture in this shader already takes at the same moment.
uniform float strata_strength : hint_range(0.0, 1.0) = 0.0;
// MEAN bed thickness in metres -- mean, not fixed; see `strata_thickness_jitter`.
uniform float strata_height = 15.0;
// How far bed boundaries move off the regular stack, as a fraction of a bed.
// Equal beds are the failure mode here: a constant thickness reads as a comb, and
// worse, it gives the eye a ruler to measure the cliff against. Must stay under
// 1.0 or boundaries cross and the three-candidate lookup breaks.
uniform float strata_thickness_jitter : hint_range(0.0, 0.9) = 0.55;
// Bed-to-bed spread, as a fraction either side of neutral. 0.3 means beds run
// 0.7x to 1.3x the rock's own colour.
uniform float strata_contrast : hint_range(0.0, 1.0) = 0.3;
// THE CONTACT IS THE FEATURE. What reads as strata from a kilometre out is the
// line between two beds, not the beds. Width is in bed units; depth is how far
// the seam darkens.
uniform float strata_contact : hint_range(0.0, 0.4) = 0.12;
uniform float strata_contact_depth : hint_range(0.0, 1.0) = 0.35;
// Per-bed hue, taken off the same hash that sets its value: iron-stained at one
// end, leached and pale at the other. Both are near luminance 1 on purpose -- the
// VALUE comes from `strata_contrast`, and these only tint it. Raw multipliers, not
// `source_color`, matching `rock_tint` and the other tints in this file.
uniform vec3 strata_tint_lo = vec3(1.10, 1.00, 0.88);
uniform vec3 strata_tint_hi = vec3(0.94, 0.98, 1.06);
// Lateral waver: metres of vertical wander, over this many metres of ground. Beds
// are not spirit-levelled, and a dead-level contact across a 760 m hillside is the
// one thing that gives the whole effect away as a shader.
//
// It is ALSO the only term that can put one bed at two different altitudes in two
// places, so it is bounded by the thing it would otherwise cost. Beds measure
// 13.1 m mean, so +/- 6 m at each of two sites lets one sit 12 m out between them
// -- nearly a whole bed, at which point world Y has bought nothing. 3 measures
// +3.8 m between faces 3 km apart. See `tests/RENDER_strata_swatch.gd`.
uniform float strata_waver = 3.0;
uniform float strata_waver_scale = 260.0;
// The ledge. A contact is a notch, so it tilts the normal about the horizontal --
// this is the term that makes the band catch the light differently above and below
// the line instead of reading as a painted stripe.
uniform float strata_relief : hint_range(0.0, 2.0) = 0.5;

group_uniforms sand;
// `coast_sand_02` -- gritty bunker sand.
uniform sampler2D sand_albedo : source_color, hint_default_white, filter_nearest_mipmap, repeat_enable;
uniform sampler2D sand_normal : hint_normal, filter_nearest_mipmap, repeat_enable;
uniform float sand_scale = 4.0;
uniform vec3 sand_tint = vec3(1.0);

group_uniforms crater;
// THE CRASH SITE. Two more ground layers and one emissive term, all gated on a
// single weight that is zero across the whole island but the one crater on it.
//
// THE WEIGHT RIDES IN UV.y AS A NEGATIVE NUMBER, sharing that float with the
// build-pad grooming weight, which is positive; the MOLTEN CORE rides the same
// way in UV.x, sharing with the fairway. `SCRIPT_chunk_mesher.gd`'s write site carries
// the argument for why the crater got signs rather than extra vertex channels;
// the consequence here is two `clamp`s and no new attribute. Note this shader
// already read `clamp(UV.y, 0.0, 1.0)` as `build` and then never used it
// — cleared earth IS the soil layer — so the positive half stays exactly as
// inert as it was.
//
// WHICH LAYER EACH REPLACES IS DECIDED CPU-SIDE, in `IslandField.splat_weights`,
// and this shader only resolves the choice to a texture — exactly what UV.x
// already does for the fairway and UV2.y for the trail. The field moves the
// crater's ground into SOIL where the blast dusted it and into ROCK where it
// scoured, off the LANDFORM slope, and those two arrive here as charred dirt and
// fused slag. Doing that angle rule here instead would have to work off the
// interpolated mesh normal, which inside a crater is the CRATER's normal — so
// the bowl would repaint its own walls, and the classification would swim as the
// LOD ladder changed how well the bowl was resolved. Having the good normal is
// the whole reason the splat is computed on the mesher.
uniform sampler2D char_albedo : source_color, hint_default_white, filter_nearest_mipmap, repeat_enable;
uniform float char_scale = 3.0;
uniform vec3 char_tint = vec3(1.0);
// Fused floor. ALPHA IS THE CRACK HEAT, not coverage — see
// `textures/proc/TOOL_gen_crater_textures.py`. `hint_default_black` rather than the
// white every other layer defaults to: unbound, white would paint the floor as a
// bright plate AND read alpha = 1, which is the whole crater at full glow. Black
// fails as a hole in the ground, which is at least the right shape.
uniform sampler2D slag_albedo : source_color, hint_default_black, filter_nearest_mipmap, repeat_enable;
uniform float slag_scale = 12.0;
uniform vec3 slag_tint = vec3(1.0);

// HOW HOT. Multiplies the ramp and routinely takes the result past 1.0, which is
// the point: the Environment runs `glow_enabled`, so this is the dial that
// decides whether the cracks are merely lit or actually radiating.
uniform float crack_glow : hint_range(0.0, 8.0) = 2.6;
// The palette ramp the cracks cycle through: `palette/TEX_ember_ramp_ps1-soft.png`,
// eight texels, cold coal at 0 and gold at 1 — THE SAME EIGHT the burning
// vegetation uses. Sharing it is not thrift. `SHADER_post_dither.gdshader` snaps the
// frame to a sixteen-entry LUT built from the same palette, so a second fire
// ramp would be quantised onto this one anyway and the two fires would agree
// only by accident; and when the burnt vegetation is rolled into the crater the
// embers on the stumps and the light in the ground are already the same colours.
//
// Bound in the material here rather than by `VegBurn`, which resolves it at
// runtime because both scatters duplicate their material once per sprite. There
// is exactly one terrain material and nothing for it to disagree with.
//
// UNBOUND IT IS WHITE, deliberately, and for the reason `veg_billboard` gives:
// there is no sane fallback for a missing palette, and a silent orange one would
// hide the mistake.
uniform sampler2D crack_ramp : source_color, hint_default_white, filter_nearest, repeat_disable;
// Ramp steps per second. The wave is a triangle, so this is the round trip from
// a texel's own heat to the top of its swing and back.
uniform float crack_cycle_speed : hint_range(0.0, 12.0) = 1.1;
// How far the wave moves a texel through the ramp, as a fraction of the whole.
// 0 switches the animation off and leaves the ramp as a plain heat lookup.
uniform float crack_cycle_depth : hint_range(0.0, 1.0) = 0.42;
// How far apart in the cycle two neighbouring cracks sit — the phase scatter,
// in whole trips round the ramp across the baked heat's full range. 0 puts the
// entire network on one clock, which reads as a floor with a switch on it.
uniform float crack_cycle_scatter : hint_range(0.0, 16.0) = 3.5;

// THE MOLTEN CORE. `IslandField.crater_molten` decides how much of the floor is
// still liquid and the mesher hands it over in -UV.x; these three decide what
// that looks like.
//
// WHY A GAMMA AND NOT A MULTIPLIER, which is the only real idea in the block.
// The baked alpha is a NARROW heat core threaded down the middle of each seam —
// `TOOL_gen_crater_textures.py` sets it at 0.055 of the plate distance on purpose, so
// an ordinary crack reads as a bright line in a dark groove. A multiplier makes
// those same lines brighter and nothing else; the surface stays a cracked crust
// with a light turned up. `pow` with an exponent under 1 makes them WIDER: at
// 0.30 a texel at 0.03 goes to 0.35 and one at 0.30 goes to 0.70, so the seams
// swell until the plates between them are islands in a lit field. That is the
// difference between hot rock and molten rock, and it is one instruction.
//
// Its natural limit is the right one too. As the exponent falls the field goes
// to 1 everywhere the bake left ANY heat and stays 0 where it left none — which
// is the cooled rafts, drawn by the same Worley network as the cracks. So the
// pool that appears at the extreme is a pool with crust floating on it rather
// than a disc of light, at no extra cost and with no second mask to keep in step.
uniform float melt_gamma : hint_range(0.05, 1.0) = 0.30;
// Extra glow at the core, ON TOP of `crack_glow`. The pool is nearer the
// Environment's bloom threshold than the seams out on the floor are, which is
// most of what says it is the deep end.
uniform float melt_glow : hint_range(0.0, 6.0) = 1.6;
// How far the widened field is allowed to darken the plate it swells over, so
// the rafts read as crust ON something rather than as the surface itself. Small:
// this is a correction to the contrast the added light costs, not an effect.
uniform float melt_shade : hint_range(0.0, 1.0) = 0.35;
//
// THERE IS NO SEPARATE "WHERE IS IT HOT" THRESHOLD, and that is deliberate. The
// obvious build gives the glow its own onset on the char weight, tuned to sit
// above the lip so the rim stays cold. It is redundant: the cracks live in the
// SLAG, the slag is the rock channel, and `IslandField.splat_weights` has already
// decided — from the landform slope, in the one place the good normal exists —
// that the lip and the ash apron are not slag. Gating on the rock weight makes
// the cracks appear exactly where the fused ground is, by construction rather
// than by two numbers agreeing; a second threshold could only ever disagree with
// the first, and the way it would fail is a ring of light hanging in the air over
// unfused dirt.
//
// THE MOLTEN CORE IS NOT THAT THRESHOLD, though it is radial and it does make the
// middle hotter. It does not decide WHETHER a texel glows — the rock weight still
// does, and the core multiplies through it — only how far the seams have opened.
// Where the slag ends the core is already zero, so the two can no more disagree
// than one number can.

group_uniforms divot;
//
// THE ESCAPE POD'S DENT, which is the crash site's problem with the fire taken
// out: ground that has been TORN rather than burnt. The weight rides in UV2.x as
// a negative number, sharing that float with the forest litter, and the mesher's
// write site carries the argument for the sign and for why the divot wins the
// overlap. `IslandField.divot_scuff` has already remapped it, so what arrives is
// how torn the ground looks and not where in the dent it is.
//
// THERE IS NO SEVENTEENTH SAMPLER, AND THIS BLOCK IS WHAT THAT COSTS. The header
// counts sixteen against the sixteen texture image units GLES3 guarantees, so a
// dedicated `divot_albedo` was never available: the choice was between giving
// the dent no surface of its own and finding a channel for one. What it has
// instead is a SCUFF FIELD BAKED INTO `char_albedo`'s ALPHA — clods, drag streaks
// and grit, written by `tools/TOOL_gen_crater_textures.py` alongside the char
// itself, in the channel that plate was not using. The two features never share
// a fragment (`IslandField.divot_crater_clearance` is 420 m), so one sampler
// carrying both a crater's charred RGB and a divot's torn alpha costs nothing at
// any pixel, and the alternative — a second plate — costs a unit that does not
// exist. The slag's crack heat rides in its own alpha for exactly this reason
// one block up; this is the same trick with the same justification.
//
// EVERYTHING ELSE IS GRADED OFF LAYERS ALREADY FETCHED. `soil_a` is the churned
// earth and `rock_a` is the grit and the scarp, both already sampled for this
// fragment, so the dent costs ONE extra fetch inside its own footprint and
// nothing anywhere else.
//
// Metres per tile for the scuff field. Finer than `char_scale` (3.0) because the
// dent is 20 m long and a 3 m clod pattern would repeat six times down it and
// read as a printed texture rather than as ground.
uniform float divot_scale = 1.7;
// The grade of turned earth against the surface soil it replaces. Freshly opened
// ground is darker and warmer than the dry crust over it, and this is the whole
// of what says the dirt in the dent is not the dirt around it.
uniform vec3 divot_tint = vec3(0.82, 0.74, 0.66);
// How hard the scuff field breaks the churned ground's brightness up — clods
// catching the light, the hollows between them not. Bounded well under 1: this
// is a modulation on a surface, and at 1 the field stops being relief and starts
// being a pattern printed on the floor.
uniform float divot_break : hint_range(0.0, 1.0) = 0.45;
// How much of the ROCK layer comes up through the churned earth where the field
// is high: stones turned out of the topsoil, which is what a heavy thing dragged
// through ground actually leaves behind.
uniform float divot_grit : hint_range(0.0, 1.0) = 0.30;
// And the grade on the bank's cut face. The rock channel is already carrying it
// — `IslandField.splat_weights` hands scarped ground to rock the way it hands
// fused ground to slag — so this only says that a fresh cut is paler and drier
// than weathered cliff, which is the difference between a scarp and an outcrop.
uniform vec3 divot_scarp_tint = vec3(1.08, 1.05, 1.0);

group_uniforms lighting;
uniform float normal_strength : hint_range(0.0, 2.0) = 0.6;
// Cheap ambient-occlusion-ish darkening on steep ground, carried over from the
// flat-colour shader so relief still reads where the texture has little tonal
// range of its own.
uniform float slope_shade : hint_range(0.0, 1.0) = 0.18;
// FLAT (faceted) shading. Off: the per-fragment normal is the mesh's
// interpolated one, which `SCRIPT_chunk_mesher.gd` computes analytically from the
// height field rather than by averaging faces, so it is smooth and continuous
// across chunk and LOD boundaries by construction. On: the geometric FACE normal
// recovered from screen-space derivatives of world position, oriented into the
// mesh normal's hemisphere because the raw cross-product sign is not dependable.
//
// Keep this in step with `MAT_cliff_gradient.tres`. The plateau and the cliff are
// separate meshes, so the coastline between them is a hard crease either way --
// but one faceted and one smooth makes that crease read as a seam rather than as
// an edge, which is why the test asserts the pair.
uniform bool flat_shading = false;

group_uniforms island_light;
// The unlit shading model's knobs. The COLOURS are not here — they are the four
// `tod_*` globals on the bus, so a day/night cycle moves the whole island (and the
// water spray, and the rainbow arc) without touching a material. These four are the
// SHAPE of the response, which is a per-surface art choice.
//
// `MAT_cliff_wall.tres` carries the same four, and has to: the wall continues this
// surface across a shared ring in plain sight, so a different response curve either
// side of it is a seam in the shading exactly where the albedo was made seamless.
uniform float sun_bands : hint_range(0.0, 12.0) = 4.0;
uniform float sun_wrap : hint_range(0.0, 1.0) = 0.35;
uniform float rim_power : hint_range(0.5, 8.0) = 3.0;
uniform float rim_strength : hint_range(0.0, 2.0) = 0.25;

group_uniforms void_fog;
// W2's own band, and NOT `SHADER_terrain_splat.gdshader`'s: one colour rather than a
// high/low pair, and a higher onset. `fog_color` is an EXACT NEUTRAL matching the
// sky's bottom colour -- a tint here loses to a tinted palette-LUT entry and
// stripes the view. See MAT_terrain_flatcolor.tres, which this is copied from.
//
// "AN EXACT NEUTRAL" IS STILL TRUE OF THE AUTHORED VALUE and is no longer true of
// what reaches the screen, because of `tod_haze_tint` below. The reasoning is
// unchanged -- the fogged distance and the empty sky behind it have to resolve to
// the SAME palette entry -- but the value they agree on is now a product, and the
// sky's `bottom_color` is the same product. See the tint's own note.
uniform bool fog_enabled = true;
uniform vec3 fog_color : source_color = vec3(0.089, 0.089, 0.089);
uniform float fog_top = -170.0;
uniform float fog_bottom = -320.0;
uniform float fog_curve : hint_range(0.25, 6.0) = 2.2;
uniform float fog_opacity_gain : hint_range(1.0, 6.0) = 1.6;
uniform float fog_distance_start : hint_range(0.0, 3000.0) = 850.0;
uniform float fog_distance_density : hint_range(0.0, 0.01) = 0.0012;
uniform float fog_distance_power : hint_range(1.0, 4.0) = 2.0;

// THE HAZE BUS: a MULTIPLIER on `fog_color`, published by
// `scripts/SCRIPT_sky_cycle_controller.gd`.
//
// The whole of SCENE_test_zone_W2 is pinned to ONE haze value -- fourteen
// materials, the Environment's fog and the sky's own `bottom_color`, all at the
// exact neutral 0.30 -- and that pin is why the cycle could never be turned on
// there: recolour the sun and the world recolours against a horizon that does not.
// Putting the haze on the bus as a tint moves all fourteen at once and, because
// the sky's bottom is written as the same `base * tint` product, moves them to a
// value they still agree on.
//
// WHITE IS THE DEFAULT everywhere -- in project.godot, and at all three phases of
// the cycle -- so a scene that has not authored a haze tint renders exactly what
// it rendered before this line existed. That is what buys the change out of
// needing a per-material enable flag. See the Haze group in the controller.
global uniform vec4 tod_haze_tint;

group_uniforms;


// Top-projected normal sample, returned as a perturbation in world XZ.
vec3 sample_top_normal(sampler2D nrm, vec2 uv) {
	vec3 t = texture(nrm, uv).xyz * 2.0 - 1.0;
	return vec3(t.x, 0.0, t.y);
}


// ---- strata ----------------------------------------------------------------
// The bed stack is COMPUTED, not sampled, and the reason is the sampler budget in
// the header: fourteen samplers here plus `env_ball` and `env_ball_night` from the
// include is sixteen of the sixteen GLES3 guarantees, so there is no seventeenth
// to bind a strata texture to. (The header's "fifteen ... room for one more" is a
// count from before the night ball landed. There is no room.)
//
// It is also the better data structure for this particular signal, which is worth
// saying because it is not obvious. A bed is a function of ALTITUDE ALONE: baked as
// a 2D tile the field measures ~950x more variance down the tile than across it,
// so a texture would spend an entire axis storing a constant, and would still
// repeat every tile-height of cliff. These three hashes do not repeat at all.

float strata_hash(float n) {
	return fract(sin(n * 127.1) * 43758.5453123);
}


// The boundary plane ABOVE bed `i`, in stack units (1.0 = one mean bed). Jitter is
// clamped below 1.0 by the caller, which keeps this sequence monotonic in `i` --
// that is what lets the lookup test three candidate beds instead of searching.
float strata_bound(float i, float jitter) {
	return i + (strata_hash(i * 1.7 + 11.3) - 0.5) * jitter;
}


// Value noise on the horizontal plane, for the lateral waver. Two-dimensional
// because a bed wanders in map view; it is deliberately NOT a function of Y, since
// anything that made band altitude depend on X or Z would tilt the beds -- see the
// note on dip in the `strata` uniform block.
float strata_vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	const vec2 k = vec2(1.0, 57.0);
	float a = strata_hash(dot(i, k));
	float b = strata_hash(dot(i + vec2(1.0, 0.0), k));
	float c = strata_hash(dot(i + vec2(0.0, 1.0), k));
	float d = strata_hash(dot(i + vec2(1.0, 1.0), k));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}


void fragment() {
	vec3 world_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;

	vec3 smooth_n = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 world_normal;
	if (flat_shading) {
		vec3 fn = normalize(cross(dFdx(world_pos), dFdy(world_pos)));
		world_normal = dot(fn, smooth_n) < 0.0 ? -fn : fn;
	} else {
		world_normal = smooth_n;
	}
	// NO FRONT_FACING FLIP. The terrain is a single-layer shell drawn
	// `cull_disabled`, and under that the engine has already turned NORMAL toward
	// the viewer on a back face before this runs (`PROBE_ruin_light_normals.gd`
	// measures it on 4.7 GLES3). The `if (!FRONT_FACING)` flip that stood here
	// turned it away again, so every back face was lit as its own front: the
	// underside of the ground, seen from below, came out sunlit.

	vec4 w = max(COLOR, vec4(0.0));
	w /= max(w.x + w.y + w.z + w.w, 1e-5);

	float golf = clamp(UV.x, 0.0, 1.0);
	float build = clamp(UV.y, 0.0, 1.0);
	float forest = clamp(UV2.x, 0.0, 1.0);
	float path = clamp(UV2.y, 0.0, 1.0);
	// The other halves of the two UV floats — see the `crater` uniform block.
	// Each side clamps the other away, so the two never see each other.
	float charred = clamp(-UV.y, 0.0, 1.0);
	float molten = clamp(-UV.x, 0.0, 1.0);
	// ...and UV2's, which is the pod's dent against the forest litter.
	float torn = clamp(-UV2.x, 0.0, 1.0);

	// ---- ground layers: one top projection each ---------------------------
	vec2 p = world_pos.xz;
	vec3 grass_a = texture(grass_albedo, p / max(grass_scale, 1e-4)).rgb * grass_tint;
	vec3 soil_a = texture(soil_albedo, p / max(soil_scale, 1e-4)).rgb * soil_tint;
	vec3 sand_a = texture(sand_albedo, p / max(sand_scale, 1e-4)).rgb * sand_tint;
	vec3 forest_a = texture(forest_albedo, p / max(forest_scale, 1e-4)).rgb * forest_tint;

	// Forest first, grooming over the top of it: where a deliberate surface and a
	// wood would meet, the deliberate one wins. They cannot actually overlap --
	// `IslandField.forest_at` multiplies the mask out by the zone weight -- so this
	// is belt and braces rather than an assumption.
	grass_a = mix(grass_a, forest_a, forest * forest_grass_mix);
	soil_a = mix(soil_a, forest_a, forest);

	// Mown fairway lifts the grass channel; the trail takes over the soil channel.
	// Build pads need no mix at all: cleared earth IS the soil layer, which is why
	// `build` only appears in the roughness blend below.
	if (golf > 0.0) {
		vec3 golf_a = texture(golf_albedo, p / max(golf_scale, 1e-4)).rgb * golf_tint;
		grass_a = mix(grass_a, golf_a, golf);
	}
	if (path > 0.0) {
		vec3 path_a = texture(path_albedo, p / max(path_scale, 1e-4)).rgb * path_tint;
		soil_a = mix(soil_a, path_a, path);
	}
	if (build_paving > 0.0 && build > 0.0) {
		vec3 pave_a = texture(build_albedo, p / max(build_scale, 1e-4)).rgb;
		soil_a = mix(soil_a, pave_a, build * build_paving);
	}

	// ---- rock: full triplanar, it has to cover the cliffs -----------------
	vec3 bw = pow(abs(world_normal), vec3(triplanar_sharpness));
	bw /= max(bw.x + bw.y + bw.z, 1e-5);
	float rs = max(rock_scale, 1e-4);
	vec3 rock_a = (texture(rock_albedo, world_pos.zy / rs).rgb * bw.x
			+ texture(rock_albedo, world_pos.xz / rs).rgb * bw.y
			+ texture(rock_albedo, world_pos.xy / rs).rgb * bw.z) * rock_tint;

	// ---- the steep stone (see `steep_stone`) --------------------------------
	float st = 0.0;
	if (steep_stone > 0.0) {
		st = smoothstep(steep_lo, steep_hi, 1.0 - smooth_n.y) * steep_stone;
		if (st > 0.0) {
			float ss = max(stone_scale, 1e-4);
			vec3 stone = texture(stone_albedo, world_pos.zy / ss).rgb * bw.x
					+ texture(stone_albedo, world_pos.xz / ss).rgb * bw.y
					+ texture(stone_albedo, world_pos.xy / ss).rgb * bw.z;
			stone = mix(stone_mean, stone, stone_contrast) * stone_tint;
			rock_a = mix(rock_a, stone, st);
			w = mix(w, vec4(0.0, 0.0, 1.0, 0.0), st);
			golf *= 1.0 - st;
			path *= 1.0 - st;
			build *= 1.0 - st;
		}
	}

	// ---- strata: the cliff-face overlay -----------------------------------
	// See the `strata` uniform block for what this is and why it is computed
	// rather than sampled. Two nested branches, and which one is which matters:
	// the OUTER tests a uniform, so every fragment in the draw takes the same
	// path and `fwidth` below is well defined; the INNER tests `w.z`, which is
	// not uniform, so nothing needing a screen-space derivative may sit inside
	// it. That is the whole reason `fw` is computed where it is.
	vec3 strata_n = vec3(0.0);
	if (strata_strength > 0.0) {
		float sh = max(strata_height, 1e-4);
		// Beds per pixel. The overlay DISSOLVES as this approaches one, which is
		// the analytic answer to the one thing a computed band stack has that a
		// mipmapped texture does not: past about half a bed per pixel the stack
		// is no longer resolvable and sampling it can only shimmer. It fades at
		// roughly the range the distance fog is taking it anyway.
		float fw = fwidth(world_pos.y / sh);
		// SIDE PROJECTION: bw.y, the top plane, is dropped. This is the gate.
		float side = bw.x + bw.z;
		float amount = strata_strength * side * (1.0 - smoothstep(0.25, 0.8, fw));
		// `w.z` gates the WORK here, not the blend. The strata modulate `rock_a`,
		// and the combine further down already weights that channel by `w.z`;
		// folding it into the blend as well would square it and fade the beds out
		// across exactly the ground the splat is handing to rock.
		if (amount * w.z > 0.002) {
			float waver = (strata_vnoise(world_pos.xz / max(strata_waver_scale, 1e-4)) - 0.5)
					* 2.0 * strata_waver;
			float y = (world_pos.y + waver) / sh;
			float jitter = clamp(strata_thickness_jitter, 0.0, 0.9);
			// Which bed. Every boundary moves less than half a bed off the regular
			// stack, so `y` can only belong to the bed under `floor(y)`, that one,
			// or the one over it -- three tests, no search, no loop.
			float i0 = floor(y);
			float bed = i0;
			if (y < strata_bound(i0, jitter)) {
				bed = i0 - 1.0;
			} else if (y >= strata_bound(i0 + 1.0, jitter)) {
				bed = i0 + 1.0;
			}
			float below = y - strata_bound(bed, jitter);
			float above = strata_bound(bed + 1.0, jitter) - y;
			// One hash sets both the bed's value and its hue, so a pale bed is
			// always the cool one. They are the same rock; they should not be able
			// to disagree about which rock.
			float tone = strata_hash(bed * 3.1 + 0.7);

			// The contact, widened to at least a pixel and a half so the seam
			// blurs as it recedes rather than crawling.
			float edge = max(strata_contact, fw * 1.5);
			float t = clamp(min(below, above) / edge, 0.0, 1.0);
			float s = smoothstep(0.0, 1.0, t);
			float v = 1.0 + (tone - 0.5) * 2.0 * strata_contrast;
			v *= 1.0 - strata_contact_depth * (1.0 - s);
			rock_a = mix(rock_a, rock_a * mix(strata_tint_lo, strata_tint_hi, tone) * v, amount);

			// THE LEDGE, and it is the seam's own gradient rather than a second
			// field: `s` is a smoothstep, so ds/dt is 6t(1-t) exactly. That peaks
			// mid-ramp and vanishes at both ends, so the normal bends into the
			// notch and comes back out flat -- no crease across the middle of a
			// bed, where nothing is happening.
			//
			// Sign: just above a contact the face is climbing back out of the
			// groove, so the surface rises along +Y and its normal tilts -Y.
			float g = below < above ? -1.0 : 1.0;
			strata_n = vec3(0.0, g * 6.0 * t * (1.0 - t) * strata_relief, 0.0)
					* amount * w.z;
		}
	}

	// ---- the pod's divot ---------------------------------------------------
	// Torn earth takes over the soil channel and the scarp grades the rock one,
	// which is the same move the crash site makes below and the trail and the
	// fairway make above. It runs BEFORE the crash site for no reason of
	// precedence — the two are 420 m apart and cannot both be non-zero — but
	// after the rock block, which does matter: the bank's cut face is the
	// steepest ground the dent has, and grading a rock colour the triplanar
	// blend has not run on yet would grade a stretched one.
	if (torn > 0.0) {
		// The scuff field, and the only fetch this feature costs. See the
		// uniform block for why it is riding in the char plate's alpha.
		float scuff = texture(char_albedo, p / max(divot_scale, 1e-4)).a;
		// Churned earth: the soil layer, regraded and broken up by the field.
		vec3 turned = soil_a * divot_tint * (1.0 - divot_break * (1.0 - scuff));
		// ...with stones turned out of it where the field is highest.
		turned = mix(turned, rock_a, divot_grit * scuff);
		soil_a = mix(soil_a, turned, torn);
		// And the cut face. Scoped by `torn` so the weathered rock a metre
		// outside the dent is untouched.
		rock_a *= mix(vec3(1.0), divot_scarp_tint, torn);
	}

	// ---- the crash site ---------------------------------------------------
	// Charred dirt takes over the soil channel and fused slag the rock channel,
	// which is the same move the trail and the fairway make on theirs. Both
	// borrow their base's normal map, for the reason in the header: they are
	// ground at the same relief scale as the layer they replace, and it is the
	// albedo the eye reads.
	//
	// After the rock block rather than before it, so the slag mixes over a rock
	// colour that has already been triplanar-blended. That matters on the bowl
	// walls, which are the steepest ground the crater has and the only part of it
	// where the top projection alone would stretch. The divot above sits
	// between the strata and this for the same reason.
	vec3 crack_light = vec3(0.0);
	if (charred > 0.0) {
		vec3 char_a = texture(char_albedo, p / max(char_scale, 1e-4)).rgb * char_tint;
		soil_a = mix(soil_a, char_a, charred);
		vec4 slag_s = texture(slag_albedo, p / max(slag_scale, 1e-4));
		rock_a = mix(rock_a, slag_s.rgb * slag_tint, charred);

		// THE GLOWING CRACKS. `slag_s.a` is the heat baked into the seams and
		// says WHERE in the texture the light is; the ROCK WEIGHT says where in
		// the world the slag is, and is the whole of the gate — see the uniform
		// block. Without it the seams would light up through the charred dirt on
		// the apron, which has no fused ground under it at all.
		float baked = clamp(slag_s.a, 0.0, 1.0);
		// AT THE CORE THE SAME NETWORK OPENS UP. See `melt_gamma`: this is the
		// whole of "more molten toward the middle", and it is deliberately one
		// field widened rather than a second effect faded in. A separate pool
		// term would have its own outline, and a second outline inside a crater
		// floor is a ring — which is the one shape a melt does not have.
		float hot = baked;
		if (molten > 0.0) {
			hot = mix(baked, pow(baked, max(melt_gamma, 0.05)), molten);
			// The plate darkens as the field swells over it, so the cooled rafts
			// stay rafts. Scoped to the GAIN rather than to `hot` itself, so a
			// texel the bake left cold — the middle of a raft — is not darkened
			// for sitting next to something that is not.
			rock_a *= 1.0 - melt_shade * molten * clamp(hot - baked, 0.0, 1.0);
		}
		float heat = hot * w.z;
		if (heat > 0.0) {
			// The ramp's length off the texture rather than off a uniform, so
			// the two cannot disagree; unbound it is 1x1 and the guard leaves
			// every lookup on the single (white) texel.
			int steps = textureSize(crack_ramp, 0).x;
			float span = float(max(steps - 1, 1));
			// THE PHASE IS SCATTERED PER TEXEL, NOT SWEPT ACROSS THE CRATER,
			// and that is a correction rather than a preference. The plants get
			// a band that CLIMBS because `TOOL_gen_burn_maps.py` bakes a burn ORDER
			// per texel and the phase runs against it. A crater floor has no
			// equivalent axis: the two quantities here that look radial are the
			// char weight and the rock weight, and both are pinned flat at 1
			// across the whole floor — which is exactly where the cracks are. A
			// phase gradient on either is a gradient over nothing, and what it
			// draws is the entire network flashing in unison.
			//
			// The baked heat is per texel and is not flat, so it is what keeps
			// two neighbouring cracks out of step. Same role `bm.r` plays in
			// `SHADER_veg_billboard.gdshader`'s phase, minus the climb it cannot have.
			//
			// SCATTERED ON `baked`, NOT ON `hot`, and that is the one place the
			// molten term must not reach. `pow` flattens the field as it widens
			// it — that is what widening IS — so a phase taken off the widened
			// value converges as the pool deepens, and the middle of the crater
			// would pulse in unison. The texel's own baked heat is a fixed
			// property of the texture and keeps its clock wherever it is.
			float ph = TIME * crack_cycle_speed + baked * crack_cycle_scatter;
			float wave = abs(fract(ph) * 2.0 - 1.0) - 0.5;
			// Scoped to the live seams the way the plants scope theirs to the
			// flame: a hot crack cycles hard, a cooling one only shimmers.
			float swing = crack_cycle_depth * (0.30 + 0.70 * heat);
			// Indexed by the WIDENED heat, so the pool sits further up the ramp
			// than the seams out on the floor do and reads as gold against their
			// orange — but not by `heat`, which has the rock weight folded in and
			// would recolour the whole network as the crater faded out at its
			// edge instead of dimming it.
			float idx = clamp(hot + wave * 2.0 * swing, 0.0, 1.0);
			// Quantise to a whole step BEFORE the lookup. This is the difference
			// between indexed colour flipping and a gradient sliding.
			vec3 hue = texture(crack_ramp,
					vec2((floor(idx * span) + 0.5) / float(steps), 0.5)).rgb;
			crack_light = hue * heat * (crack_glow + melt_glow * molten);
		}
	}

	// ---- normals ----------------------------------------------------------
	vec3 grass_n = sample_top_normal(grass_normal, p / max(grass_scale, 1e-4));
	vec3 soil_n = sample_top_normal(soil_normal, p / max(soil_scale, 1e-4));
	vec3 sand_n = sample_top_normal(sand_normal, p / max(sand_scale, 1e-4));
	vec3 rnx = texture(rock_normal, world_pos.zy / rs).xyz * 2.0 - 1.0;
	vec3 rny = texture(rock_normal, world_pos.xz / rs).xyz * 2.0 - 1.0;
	vec3 rnz = texture(rock_normal, world_pos.xy / rs).xyz * 2.0 - 1.0;
	// UDN-style perturbation: each projection's tangent xy drives the two world
	// axes that projection spans.
	vec3 rock_n = vec3(0.0, rnx.y, rnx.x) * bw.x
			+ vec3(rny.x, 0.0, rny.y) * bw.y
			+ vec3(rnz.x, rnz.y, 0.0) * bw.z;

	// ---- combine ----------------------------------------------------------
	vec3 albedo = grass_a * w.x + soil_a * w.y + rock_a * w.z + sand_a * w.w;
	// `strata_n` carries its own `w.z` (see the strata block) rather than taking
	// one here: it is a modifier on the rock channel, not a fifth channel.
	vec3 npert = grass_n * w.x + soil_n * w.y + rock_n * w.z + sand_n * w.w + strata_n;

	vec3 shaded_n = normalize(world_normal + npert * normal_strength);
	float slope = clamp(1.0 - world_normal.y, 0.0, 1.0);
	albedo *= 1.0 - slope * slope_shade;

	// UNLIT: this multiply IS the lighting. `VIEW` is the fragment->camera vector in
	// view space, so INV_VIEW_MATRIX takes it to the world frame the normal is
	// already in.
	vec3 world_v = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	albedo *= island_light(shaded_n, world_v, sun_bands, sun_wrap, rim_power, rim_strength);
	// the stone down the island's side going over to the sea's darkest grey
	if (deep_on && st > 0.0) {
		float deep = 1.0 - smoothstep(sea_surface_y + deep_bottom,
				sea_surface_y + max(deep_top, deep_bottom + 1.0), world_pos.y);
		albedo = mix(albedo, deep_color, deep * st);
	}

	// THE CRACKS ARE THEIR OWN LIGHT, so they are ADDED after the shading model
	// rather than multiplied through it. A seam radiating past 1.0 is not
	// something the sun's angle should be able to dim, and on the shadowed inner
	// wall of a bowl — which is where most of them are — that difference is the
	// entire effect: multiplied, the cracks would be darkest exactly where a
	// crater is meant to look hottest.
	//
	// BEFORE the fog, which does dim them, and should: haze sits between the
	// surface and the eye, so a crash site a kilometre out goes grey with
	// everything else instead of burning a hole through the murk. That is the
	// same ordering the surface's own shading gets, one line down.
	albedo += crack_light;

	if (fog_enabled) {
		float t = clamp((fog_top - world_pos.y) / max(fog_top - fog_bottom, 1e-3), 0.0, 1.0);
		float depth_t = clamp(pow(t, 1.0 / max(fog_curve, 0.001)) * fog_opacity_gain, 0.0, 1.0);
		float d = max(length(VERTEX) - fog_distance_start, 0.0) * fog_distance_density;
		float dist_t = 1.0 - exp(-pow(d, fog_distance_power));
		float fog = 1.0 - (1.0 - depth_t) * (1.0 - dist_t);

		// A STRAIGHT MIX, now that there is no light term to survive. This used to
		// drain ALBEDO to black, put `fog_color` in EMISSION and pull SPECULAR down
		// with it, all so that fogged geometry landed on exactly the fog colour
		// whatever the sun was doing to it. Unshaded, ALBEDO *is* the output, so the
		// mix lands on it exactly and the other two are dead. Same construction as
		// `SHADER_veg_billboard.gdshader`, which the fog constants already have to match.
		//
		// AFTER the light, deliberately: haze sits between the surface and the eye,
		// so it is not something the surface's own shading should modulate.
		albedo = mix(albedo, fog_color * tod_haze_tint.rgb, fog);
	}

	// AFTER THE FOG, AND SO AFTER EVERYTHING. The wall is a grade on the finished
	// picture, not a term in the lighting — draining before the haze would leave
	// coloured fog hanging over a grey landscape. Unshaded, so this is the pixel.
	albedo = golf_wall_drain(albedo, world_pos.xz, SCREEN_UV, TIME);

	ALBEDO = albedo;
	// THE THERMAL SIGHT's feed (godot/shaders/thermal_base.gdshaderinc):
	// only people are hot, and this is not one
	if (thermal_on(VIEWPORT_SIZE)) ALBEDO = thermal_out(thermal_cold(ALBEDO, clamp((length(VERTEX) - 700.0) / 2500.0, 0.0, 1.0)));
}
