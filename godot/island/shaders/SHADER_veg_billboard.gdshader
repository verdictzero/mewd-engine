shader_type spatial;
render_mode cull_disabled, unshaded;
#include "res://godot/shaders/thermal_base.gdshaderinc"

#include "res://godot/island/shaders/SHADERINC_golf_wall.gdshaderinc"

// The ONE shader every plant in the world is drawn with — the firs, the bushes,
// the ferns and the ground-cover grass alike. Y-axis (cylindrical) camera-plane
// billboards: the quad keeps world up and yaws to face the camera, so a plant
// reads as upright from any horizontal angle and never shears against its
// neighbours on a slope.
//
// ONE SHADER, FOUR MATERIALS, and that is the whole configuration. `SCRIPT_veg_scatter.gd`
// draws the firs through `MAT_veg_billboard.tres`, the bushes through
// `MAT_veg_understory.tres` and the ferns through `MAT_veg_fern.tres`;
// `SCRIPT_grass_scatter.gd` draws through `MAT_grass_billboard.tres`. The difference
// between a fir and a tuft of grass is entirely which texture is bound and where
// the two fade bands are set. There is no second billboard construction anywhere in
// the project any more, which is the point — the two that used to exist
// (`grass_billboard` and `tree_billboard`) drifted apart on tint, on fog and on
// what "upright" meant.
//
// THE FOUR MATERIALS ARE FOUR SIZES OF PLANT, not four looks, and both fades are
// there because the right value for each depends on how big the thing is: a 22 m
// fir is a wall at arm's length and a silhouette at a kilometre, an ankle-high tuft
// is neither at any range. Tint, fog and filtering are and should stay identical
// across all four.
//
// UNLIT. `unshaded` means ALBEDO goes straight to the screen: no sun term, no
// ambient, no normal, no shadow. That is a deliberate look, not a shortcut, and
// it removes three things that used to be here and were each their own bug —
// the `up_bias` normal fudge (a camera-facing quad has no honest normal, so it
// flipped between blown out and black as you walked round it), the roughness
// uniform, and the per-instance ground tint. What replaces all of it is `tint`,
// a flat linear multiplier that sits the painted sprite in the same exposure as
// the graded terrain. The art is already painted with its own light and shade;
// lighting it again was always double-counting.
//
// NEAREST filtering with mipmaps. The sprites are baked down to 128 or 256 px by
// `scripts/SCRIPT_crunch_art.gd` and are meant to read as pixel art, so bilinear would
// smear that back into mush at exactly the range you see it best. Mipmaps stay
// on — a 128 px texture on a 1 m quad at 80 m is far below one texel per pixel,
// and without them the field crawls.
//
// BOTH FADES ARE ORDERED BAYER 4x4 SCREEN-DOOR, the same matrix the rest of the
// project dithers with. Screen-door needs no back-to-front sort across tens of
// thousands of instances and it writes real depth, so the vegetation can never
// mis-sort against itself, against the terrain, or against the ball.
//
// AND THERE IS NO `depth_prepass_alpha`, which the shader this replaced carried.
// A prepass and a screen-door fade are incompatible by construction: the prepass
// decides depth from the ALPHA SCISSOR alone, so it writes the plant's whole
// silhouette, and the colour pass then discards most of that silhouette to the
// Bayer pattern. Every pixel in the difference has vegetation depth and no
// vegetation colour, which z-rejects the terrain, the sky and every plant behind
// it. Under GL Compatibility, with a near fade discarding most of the nearest
// plants, this drew flat hard-edged RECTANGLES the size of each near quad —
// punched through the sky in the wide shots. Ordinary `discard` in an opaque
// pass writes depth exactly where it writes colour, which is the whole point.
//
// THE NEAR FADE IS THE UNUSUAL ONE. Vegetation dithers OUT as the camera
// approaches and is gone entirely inside `near_gone`, which is the opposite of
// what a LOD fade does and is a gameplay requirement rather than a rendering
// one: the woods are dense enough to be a wall, and a wall of alpha-scissored
// quads a metre from the eye is both an occlusion problem and a fill-rate one.
// Walking into a thicket opens a clearing exactly as wide as you are.
//
// AND IT IS MEASURED AT ONE OF TWO PLACES, which decides whether it takes a
// PLANT or a piece of one — see `near_fade_whole_plant`. Per FRAGMENT (the
// default, and what every scene but SCENE_test_zone_W3 draws) the band is a
// sphere centred on the eye, so what it removes from a near plant is the patch
// of that plant closest to you: a 22 m fir three metres off keeps its canopy —
// twenty metres up, and therefore twenty metres away — and loses a hole at eye
// height that travels with the camera. The tree is still standing and still
// occluding; it now has a bite out of it. Per INSTANCE the whole quad dithers
// together at the plant's own distance, so the tree gets out of the way instead,
// and the clearing becomes the vertical cylinder the paragraph above has always
// described.
//
// Grass is exempt — it sets `near_solid` at or below `near_gone`, which switches
// the term off entirely (see `fade_near`). Standing in grass is not standing in
// a tree, and a bald ring following the player across a meadow is far worse than
// the tuft you clip through.
//
// ------------------------------------------------------------------------------
// AND IT BURNS. The burnt and burning vegetation is THIS SHADER with one more
// texture bound and one more number moved — there is no second material set to
// keep in step, no charred copy of the art, and not one extra draw call. `burn`
// runs 0 (untouched) to 1 (through the fire and cold), and every stage between is
// evaluated per texel from `burn_map`, a four-channel description of HOW each
// plant burns that `tools/TOOL_gen_burn_maps.py` derives from the sprite's own
// pixels:
//
//     R  EMBER      where coals sit and glow after the flame has gone
//     G  CHAR       how black this texel ends up
//     B  ORDER      WHEN it burns, 0 first to 1 last
//     A  FOLIAGE    how leaf-like this texel is, 0 wood to 1 leaf
//
// ORDER IS THE WHOLE MECHANISM. `burn` is one scalar per instance; the fragment
// compares it against this texel's place in the order field, so a single number
// sweeps a front up through the plant — ground fire at the base, then the lower
// branches, then the crown, ragged where the baked noise says so, and reaching the
// silhouette's fringe first because that is where the needle tips are. A plant is
// never uniformly "on fire"; it has a burning band with green above it and char
// below.
//
// NOTHING IS EVER ERODED AWAY. An earlier version of this used the fourth channel
// as an ASH LOSS field and discarded a texel once the flame had passed it, on the
// theory that a burnt plant is a thinner plant. It is, and it did not work: a
// per-texel discard against a baked noise field is a spray of holes rather than a
// plant losing its leaves, and at 128 px with `filter_nearest` it read as a bad
// dissolve — worse the closer you got, which is the opposite of what a detail
// effect should do. The burn is a COLOUR effect now. The silhouette a plant has
// when green is the silhouette it has when black, and the only thing that ever
// removes geometry is the `stump` break, which is a clean cut rather than a
// stipple.
//
// A SECOND CHARRED ALBEDO WOULD HAVE BEEN THE OBVIOUS BUILD and it cannot do any
// of that. It doubles the art, it has to be re-baked whenever `SCRIPT_crunch_art.gd`
// re-crunches a source, and it can only ever show the END of the burn. What reads
// as fire is the transition.
//
// PER INSTANCE, FROM THE SAME ANCHOR HASH THE FLIP USES, so one multimesh holds a
// whole forest at different stages of catching without a per-instance buffer or a
// second draw. See `v_burn`. `SCRIPT_veg_burn.gd` drives the island-wide number and the
// optional world-space front.
//
// AND EVERY PLANT BURNS IN ONE OF FIVE CHARACTERS, picked by a second hash off the
// same anchor: the material's own numbers, a tight creeping seam, a whole crown
// alight, a hot one that blooms, and a smoulder. A fire in a real stand is ragged
// because the fuel is, and without this a burning hillside is one effect applied
// five thousand times. It costs a `flat vec3` — see `VAR_SOFTNESS` — and
// `burn_variety` turns it off.
//
// AND ONE PLACE A PER-INSTANCE BUFFER *IS* USED: `INSTANCE_CUSTOM.x`, a burn baked
// into each plant by the scatter that placed it. It is 0 on every plant of an
// ordinary island and non-zero only around a crash site, where `SCRIPT_veg_scatter.gd`
// writes `IslandField.crater_burn` of the ground the plant stands on — so a ring of
// forest burns in a green island the bus never touched, matching the charred ground
// under it because both read the one crater weight. The five characters still apply,
// so the ring comes out as torches and smoulders rather than one stamped effect.
// See `burn_of`.
//
// THE EMBERS ARE THE ONLY THING IN THIS SHADER THAT MAY EXCEED 1.0, and that is
// how they light: the scene is `unshaded` with no emission channel, but its
// WorldEnvironment has `glow_enabled`, so an ALBEDO over 1 blooms. They are added
// AFTER the fog for that reason — a fire seen through half a kilometre of haze
// still glows through it, and mixing them toward `fog_color` first would grey them
// out at exactly the range a burning ridge is worth looking at. They are still
// attenuated by the haze, just not erased by it.
//
// AND THEIR COLOUR IS A PALETTE CYCLE rather than a constant: eight ps1-soft
// entries from cold coal to gold, indexed by a texel's heat plus a triangle
// wave that climbs the plant, quantised to whole steps so it flips between real
// palette colours instead of sliding through invented ones. The swing is scaled by
// the flame term, so it is the ACTIVELY BURNING band that animates and the char
// behind it that does not. See the `ember_ramp` uniform.
//
// AND THEN IT FALLS DOWN — the one place geometry does go. `stump` is a SECOND
// axis on top of `burn`, because a
// dead crown comes down about a year after the fire that killed it and `burn` = 1
// still has the whole silhouette standing — a black fir is a fir. At `stump` = 1
// what is left is wood: a broken trunk standing proud of its own splintered break,
// the stubs of its lowest branches, a charred root crown under a bush, bare ground
// where the ferns and the grass were. It is multiplied by the instance's own burn,
// so it does nothing to anything the fire never reached, and the two compose —
// a stump that is still smouldering is a legal state. See the `stump` uniform.

uniform sampler2D albedo_tex : source_color, filter_nearest_mipmap;
// THE LO-FI TEXEL GRID (at the user's request: "make all vegetation texel
// density consistently lo-fi, but don't overdo it, and make it
// reversible"): every plant's picture is sampled on a grid of
// `lofi_texels_per_m` texels to the metre of the plant's own size — a
// bush two metres across gets 64 texels across it, a tuft of grass 64
// (`lofi_min_texels`, the floor: at 32 the grass at your feet was
// blocks), a 14 m tree its picture's own 256, since 32 a metre would be
// more than it has — so a bush up close is near a tree's coarseness
// instead of ten times finer. The pictures are
// untouched; this is in the sampling. REVERSIBLE: set lofi_texels_per_m
// to 0 and every plant is sampled texel for texel as before. `quad_size`
// is the mesh's size in the instance's metres (the scatters set it).
uniform float lofi_texels_per_m = 32.0;
uniform float lofi_min_texels = 64.0;
uniform vec2 quad_size = vec2(1.0, 1.0);
varying flat vec2 v_cells;
// THE SAME PICTURE, FILTERED, for a plant smaller on the screen than in
// its picture (at the user's request: every sprite had "a sparkly
// outline"). Minified, a nearest fetch picks one of the several texels
// under each pixel, another as the plant sways, and at the cut-out's edge
// that is a rim of texels that come and go. Past one texel to the pixel
// the fetch is a linear one instead; up close it stays nearest, and the
// painting's own texels show. Bound to the same picture as `albedo_tex`
// by the game once the scatter stands (VegDamage.bind_smooth — not by
// the scatter itself, whose source is part of every island's bake
// digest); unbound it would be a white picture.
uniform sampler2D albedo_smooth : source_color, filter_linear_mipmap;
uniform float alpha_scissor : hint_range(0.0, 1.0) = 0.4;
// Flat LINEAR multiplier on the sprite. With `unshaded` there is no light term to
// carry exposure, so this is the ONLY thing standing between the art's own
// brightness and the screen — see MAT_veg_billboard.tres for how the shipped
// value was arrived at against the terrain's grade.
uniform vec3 tint : source_color = vec3(1.0);
// Mirror half the instances horizontally, chosen by a hash of the instance's own
// world position. Ten sprites over a hundred thousand plants is a lot of repeat;
// this doubles the apparent variety for no texture memory, no per-instance data
// and no extra draw call. Off restores the exact source art on every plant.
uniform bool flip_variants = true;

group_uniforms wind;
// Horizontal sway of the quad's TOP edge, in metres. The bottom is pinned, so a
// plant bends rather than slides. Set to 0 for a dead-still field.
uniform float wind_strength = 0.055;
uniform float wind_speed = 0.9;
// Metres per phase cycle across the world, so neighbouring plants lean together
// in gusts instead of each doing its own thing.
uniform float wind_scale = 11.0;

group_uniforms near_fade;
// True 3D camera distance, metres. Gone at or under `near_gone`, fully solid at
// or past `near_solid`. Set `near_solid` <= `near_gone` to switch the whole term
// off, which is what the grass material does.
uniform float near_gone = 3.0;
uniform float near_solid = 10.0;
// WHICH DISTANCE THE BAND ABOVE IS MEASURED AT. `false` measures it per FRAGMENT
// off `length(VERTEX)`; `true` measures it once per INSTANCE off the plant's own
// anchor, so the whole quad dithers together at one strength.
//
// THE TWO ARE DIFFERENT SHAPES, not two spellings of the same clearing. A
// per-fragment band is a sphere around the eye and it INTERSECTS a tall plant
// rather than removing it: walk up to a 22 m fir and what dissolves is the patch
// of it nearest you — a hole at eye height that travels with the camera — while
// the canopy twenty metres up stays solid. The tree goes on standing and goes on
// occluding, with a bite out of it.
//
// AND IT IS WEAKEST ON THE TALLEST PLANTS, which are the ones the fade exists
// for: the sphere's reach into a plant is set by how far away the plant is, not
// by how big it is, so the fraction of a fir it can take is smaller than the
// fraction of a bush, and the fraction of a bush smaller than the fraction of a
// tuft. A per-instance band has no such falloff — it is a vertical cylinder, and
// a tree is either getting out of your way or it is not.
//
// FALSE BY DEFAULT so every scene that has not asked for this keeps the exact
// pixels it had. SCENE_test_zone_W3 asks, through MAT_veg_billboard_w3.tres and
// MAT_veg_understory_w3.tres.
//
// It costs one mat4 multiply per vertex whether a material asks for it or not —
// four per plant, standing next to the `VIEW_MATRIX * m` the billboard already
// does on the line before it.
uniform bool near_fade_whole_plant = false;

group_uniforms far_fade;
// Solid out to `far_start`, dithered away by `far_end`. Keep `far_end` at or
// under the scatter's `view_distance` or plants pop out while still fully
// opaque.
//
// `far_end` IS ALSO THE CULL DISTANCE, and not by a convention someone has to
// remember: `SCRIPT_veg_scatter.gd` reads this parameter off each class's material and
// stops SUBMITTING a tile once every plant in it is past the figure, so retuning
// the band here moves the geometry in and out of the frame too. That is what makes
// the per-class bands a triangle budget rather than a look — see
// `MAT_veg_fern.tres`, which is the class that pays for it.
uniform float far_start = 900.0;
uniform float far_end = 1300.0;

group_uniforms fog;
// HAS TO MATCH THE TERRAIN'S. Anything drawn at range in this scene has to agree
// about the haze or it floats off the surface in the distance;
// `tests/TEST_island_world.gd` asserts these against MAT_terrain_splat_w2.tres.
uniform bool fog_enabled = true;
uniform vec3 fog_color : source_color = vec3(0.3, 0.3, 0.3);
uniform float fog_distance_start : hint_range(0.0, 3000.0) = 850.0;
uniform float fog_distance_density : hint_range(0.0, 0.01) = 0.0012;
uniform float fog_distance_power : hint_range(1.0, 4.0) = 2.0;

// The haze bus -- a multiplier on `fog_color`, white by default. Canonical note in
// `SHADER_terrain_splat_w2.gdshader`. "Has to match the terrain's" above is now also true
// of the tint, and it comes free: both read the same global.
global uniform vec4 tod_haze_tint;
// THE CLOCK A HIT IS TIMED BY (seconds; Game sets it every frame): see the
// shake in vertex().
global uniform float shake_clock;

// =============================================================================
//  THE ART BUS
// =============================================================================
//
// A multiplier on ALBEDO, published as `tod_art_tint` by
// `scripts/SCRIPT_sky_cycle_controller.gd`, and the thing that lets a day/night cycle
// reach the half of SCENE_test_zone_W2 that has no lighting model at all.
//
// THIS SHADER IS THE REASON IT EXISTS. `SHADERINC_island_light.gdshaderinc` recolours the
// terrain and the cliff the instant `tod_sun_color` and friends move, because the
// island computes its own light off those globals. Nothing here does: the header
// twenty lines up says `unshaded` means ALBEDO goes straight to the screen, no sun
// term, and the same is true of the grass, the volumetric cloud sea, the horizon
// cloud band and the smoke. Under a cycle that moved only the lit surfaces, W2's
// firs stayed noon-green over ground that had gone blood red -- which reads as a
// bug in the vegetation, not as nightfall.
//
// ALBEDO ONLY, NEVER EMISSION, and the ember block at the bottom of fragment() is
// the case that makes the rule: burning coals are a light SOURCE. They are added
// after the fog for that reason already, they are the one value in this shader
// allowed past 1.0 so the environment's glow blooms them, and a scene tint that
// dimmed them would be tinting a fire by the colour of the night it is lighting.
// Same argument covers `fire_particle`, `fire_sprite` and `molten_glow`, none of
// which read this global.
//
// WHITE BY DEFAULT, in project.godot and at all three phases, so this multiply is
// an identity in every scene that has not authored one.
global uniform vec4 tod_art_tint;

group_uniforms burn;
// The four burn fields for whichever sprite this material carries. `veg_scatter`
// and `grass_scatter` bind it themselves, alongside `albedo_tex`, by the naming
// convention in `VegBurn.map_for` — nothing wires it by hand.
//
// hint_default_transparent so an UNBOUND map reads as all-zero rather than as
// white. It is the only degenerate that fails safely: white would mean "order 1,
// loses all its alpha", which discards the entire plant the moment anything sets
// `burn`. Zero means the plant scorches and stops, which is wrong but visible.
// The scatters also pin `burn` to 0 on a material whose sprite has no map, so this
// is the second line of defence rather than the first.
uniform sampler2D burn_map : hint_default_transparent, filter_nearest_mipmap;
// 0 untouched, 1 through the fire and cold. NEGATIVE means "follow the island-wide
// `veg_burn` bus", which is the default and what the four base materials ship
// with — so with the bus at rest this shader draws exactly what it drew before the
// burn existed, and the `_burnt` materials are the ones that pin a value.
uniform float burn : hint_range(-1.0, 1.0) = -1.0;
// How far apart neighbouring plants are in the burn, as a fraction. A fire that
// takes a whole hillside at once is a wipe; this is what makes it a spread.
//
// It CLOSES AT BOTH ENDS (see `vertex`) — a field pinned to 0 has no plant alight
// in it and a field pinned to 1 has none still burning — so it is free to be
// large.
uniform float burn_variance : hint_range(0.0, 1.0) = 0.45;
// Width of one texel's transition, in order-field units. Also sets how much of a
// plant is mid-burn at once: small is a hard line creeping up the trunk, large is
// a whole crown alight together.
uniform float burn_softness : hint_range(0.02, 0.5) = 0.22;
uniform float ember_energy : hint_range(0.0, 4.0) = 1.0;
// How far the coals go out once the flame has passed. 1.0 is stone cold at
// `burn` = 1; the burnt material leaves a little in so a night-time burn scar
// still has something alive in it.
uniform float ember_cooling : hint_range(0.0, 1.0) = 0.85;
// How much the FIVE BURN CHARACTERS below are allowed to differ from each other.
// 1 is the full spread, 0 collapses them and every plant burns the way this
// material's own numbers say — which is what the shader did before they existed.
uniform float burn_variety : hint_range(0.0, 1.0) = 1.0;
// PIN EVERY PLANT TO ONE CHARACTER, 1..5. 0 is the shipped behaviour: each plant
// picks its own from a hash of where it stands.
//
// THIS IS HOW YOU LOOK AT ONE IN ISOLATION. Set it in a class's .tres — the
// scatters duplicate that material per sprite, so the duplicates inherit it — and
// every fir (or bush, or fern, or tuft) in the world burns as that character and
// nothing else. `burn_variety` is ignored while it is pinned, because asking for a
// character and then being given a blend of it and character 1 is not what anyone
// means. The numbers are 1-BASED to match the names in `VAR_SOFTNESS` below and in
// docs/DOC_burnt_vegetation.md; there is no character 0.
uniform int burn_character : hint_range(0, 5) = 0;
uniform float ember_speed = 5.0;
uniform vec3 scorch_color : source_color = vec3(0.28, 0.13, 0.045);
uniform vec3 char_color : source_color = vec3(0.26, 0.235, 0.215);
uniform vec3 ash_color : source_color = vec3(0.40, 0.385, 0.375);
// A flat TINT over the ramp below, not the fire's colour any more — that comes out
// of `ember_ramp`. Left at white on all eight shipped materials; it is here to
// cool or warm a particular scatter's fire without re-baking a palette.
uniform vec3 ember_color : source_color = vec3(1.0);

// THE PALETTE CYCLE. `palette/TEX_ember_ramp_ps1-soft.png`, eight texels wide, cold
// coal at 0 and gold at 1, and every entry taken FROM the ps1-soft palette by
// `tools/TOOL_gen_burn_maps.py` — because `SHADER_post_dither.gdshader` runs the whole
// frame through a LUT built from that same palette, so a fire colour that is not
// already an entry gets moved onto one anyway, possibly onto its own neighbour's,
// which would collapse two rungs of the cycle and take the animation with them.
//
// WHAT CYCLES. A texel's position in the ramp is its HEAT, plus a triangle wave
// that walks it a few steps up and down. The wave's phase runs against the baked
// burn ORDER, so a feature sits at a fixed phase and travels UP the plant as time
// advances — flames climbing rather than a whole silhouette pulsing. The index is
// quantised to whole ramp steps before the lookup, which is what makes it read as
// indexed colour flipping rather than as a gradient sliding.
//
// AND IT IS SCOPED TO THE ACTIVELY BURNING BAND. The depth of the wave is scaled
// by the flame term — the narrow band travelling with the front — so a plant that
// is alight cycles hard, settled coals behind it only shimmer, and cold char does
// not move at all. That is the whole reason the cycle is applied here and not to a
// screen-space palette: "actively burning" is a per-texel quantity in this shader
// and nothing downstream of it knows where the fire is.
//
// UNBOUND IT IS WHITE, which is deliberately unmistakable. There is no sane
// fallback for a missing palette and a silent orange one would hide the mistake.
uniform sampler2D ember_ramp : source_color, hint_default_white, filter_nearest,
		repeat_disable;
// Ramp steps per second. The wave is a triangle, so this is how long the round
// trip from a texel's own heat to the top of its swing and back takes.
uniform float ember_cycle_speed : hint_range(0.0, 12.0) = 1.6;
// How far the wave moves a texel through the ramp, as a fraction of the whole. 0
// switches the animation off and leaves the ramp as a plain heat lookup.
uniform float ember_cycle_depth : hint_range(0.0, 1.0) = 0.45;
// Bands visible up the plant at once. This is what turns the cycle into flames
// CLIMBING rather than the whole plant flashing together — it is a phase gradient
// along the baked burn order, so it follows the plant's own structure.
uniform float ember_cycle_climb : hint_range(0.0, 16.0) = 6.0;

// PATCHES — ACTIVE FIRE ON A PLANT THAT IS ALREADY BLACK. The `burn` sweep gives a
// front with green above it and char below, which is a plant CATCHING. This is the
// other picture: a stand that went through the fire hours ago, no green left
// anywhere, and fire still finding something to eat in a dozen places at once.
//
// It is not a stage of `burn` and could not be one. `burn` is monotonic by
// construction — every texel crosses its threshold once and stays crossed — so
// nothing in it can re-light a texel the flame has already passed. This is a
// separate term added on top, and it wants `burn` at 1.0 under it: at anything
// less the patches sit on green and read as fairy lights.
//
// 0 switches it off and costs one compare. The noise is two octaves of value noise
// in UV, scrolling, which is the only per-fragment procedural in this shader — it
// is behind the gate for that reason.
uniform float burn_patches : hint_range(0.0, 1.0) = 0.0;
// Blobs across the sprite. Low is a few big licks, high is a rash of small ones.
uniform float patch_scale : hint_range(1.0, 24.0) = 7.0;
// How fast they crawl and re-form. The plant is not moving; the fire in it is.
uniform float patch_speed : hint_range(0.0, 2.0) = 0.35;
// Depth of the moving front, in METRES of world space, when `veg_burn_front` is
// driving one. Plants this far behind the leading edge are fully through.
uniform float burn_front_depth = 120.0;

group_uniforms stump;
// WHAT IS LEFT STANDING A YEAR LATER. `burn` = 1 is a plant that has been through
// the fire and gone cold, and it still has its whole silhouette: a black fir is a
// fir. It is not what a burn scar looks like once the dead crown has come down.
// This collapses the plant to its own base — a broken trunk, a charred root crown,
// a black smear where a fern was.
//
// A SEPARATE AXIS AND NOT THE END OF `burn`, which is the decision here. Folding it
// into the same scalar would have made `burn` = 1 stop meaning "through the fire"
// and would have put the collapse on the same clock as the flame, which is wrong by
// about a year. Orthogonal, they compose: a stump that is still smouldering, a
// fresh char that has not fallen yet, and every mixture across an island.
//
// 0..1, and NEGATIVE follows the island-wide `veg_stump` bus exactly as `burn`
// follows `veg_burn`. It is also MULTIPLIED BY THE INSTANCE'S BURN, so pushing the
// bus on a green forest does nothing at all — a plant cannot collapse from a fire
// that never reached it.
uniform float stump : hint_range(-1.0, 1.0) = -1.0;
// Where the break ends up, as a fraction of the QUAD's height — measured from the
// base, which the sprites are all flush against (`SCRIPT_crunch_art.gd` fits them that
// way; bottom padding is under 6% on every one of the ten).
//
// THE TOP OF A QUAD IS NOT THE TOP OF EVERY PLANT, though, and that is why this is
// per-material rather than one constant. A fir fills its texture; a bush occupies
// the bottom three quarters of a square one and has a fifth of empty above it. So
// the same figure is a different fraction of the plant on each, which is exactly
// the kind of thing the four materials exist to hold — see each of the four
// `_stump` variants for the value its own class is set to.
uniform float stump_height : hint_range(0.02, 0.8) = 0.18;
// How far the break line wanders, off the baked foliage field — INVERTED, so the
// texels that survive the fire best are also the ones that stand highest. The
// foliage field is near zero on wood and high on leaf, so this lifts the line over the trunk
// and drops it through the branches around it: a snapped trunk standing a little
// proud of its own break. A perfectly flat cut reads as a sawn one.
//
// SMALL, AND IT WANTS TO STAY SMALL. At 0.16 this was a sixth of the quad of
// vertical wander, which is not a splintered break — it is a spray of surviving
// speckle standing where the crown was, and it read as a dead shrub rather than as
// a stump. The break is a BREAK: a couple of per cent of jitter on an otherwise
// definite line.
uniform float stump_ragged : hint_range(0.0, 0.2) = 0.06;

group_uniforms;

// THE ISLAND-WIDE FIRE, published by `scripts/world/SCRIPT_veg_burn.gd` — the same shape
// as the `tod_*` bus that lights the landmass, and for the same reason: every
// plant in the scene is drawn by a DUPLICATE of one of four materials, so a
// property of the world rather than of a sprite has nowhere else to live. Both sit
// at rest in project.godot, so a scene with no VegBurn node in it renders green.
//
//   veg_burn        0..1, how far through the fire the island is
//   veg_burn_front  xyz = origin, w = radius in metres. w <= 0 means no front and
//                   `veg_burn` applies everywhere at once.
global uniform float veg_burn;
global uniform vec4 veg_burn_front;
// And how much of what burnt has since come down — see the `stump` uniform.
global uniform float veg_stump;

// FLAT, and that is not a micro-optimisation. This is a per-INSTANCE choice, and
// interpolating it across the quad is exactly the bug this shader shipped with
// once: a `v_flip` that ramps 0 -> 1 up the quad makes `mix(UV.x, 1.0 - UV.x, t)`
// collapse toward the constant 0.5 at the halfway row, so a whole scanline samples
// ONE texture column and the sprite comes out as horizontal streaks. Where the
// collapsed column happens to be opaque the quad also stops being a cutout at all
// and fills its entire rectangle — including the transparent padding — which is
// what punched flat hard-edged blocks through the sky.
//
// `flat` alone is not enough, because a quad is two triangles with two provoking
// vertices and they could still disagree down the diagonal. What actually
// guarantees agreement is hashing the UNDISPLACED instance origin below.
varying flat float v_flip;

// This instance's own place in the fire, and its own flicker phase. Both are
// `flat` for exactly the reason `v_flip` is: they are per-INSTANCE quantities, and
// interpolating them across the quad would put the burn front at a different
// height on each corner and shear the plant's char against its own silhouette.
varying flat float v_burn;
varying flat float v_seed;
varying flat float v_stump;
// THIS PLANT'S distance to the camera, in metres, for `near_fade_whole_plant`.
// `flat`, and taken off the UNDISPLACED anchor, which is this file's rule for
// anything that has to be one value for the whole quad. From the anchor the four
// corners already agree, so `flat` costs nothing and states the intent; from the
// swayed `m[3]` they would not, and the near band would then ripple up each plant
// with the wind — the same class of bug the note above `v_flip` records, and the
// reason both quantities are derived where they are.
varying flat float v_near;
// This instance's burn character, resolved in the vertex stage: x scales
// `burn_softness`, y scales `ember_energy`, z is added to `ember_cooling`. Carried
// as a vec3 rather than as an index so the fragment never indexes a const array,
// which not every GLES3 driver is happy about.
varying flat vec3 v_char;
// HOW FAR OUTSIDE THE ENGAGED HOLE'S WALL THIS PLANT STANDS, 0..1. See
// `SHADERINC_golf_wall.gdshaderinc`.
//
// `flat`, and off the anchor, by this file's rule for anything that has to be one
// value for the whole quad — but here the rule is doing more than tidiness. A
// plant is a billboard, so interpolating the wall across its corners would drain
// and freeze it in vertical STRIPES as the boundary crossed the quad. Resolving it
// per instance makes a tree on the line pick a side and commit, which is both what
// a wall should do to a discrete object and one `golf_wall_outside` per plant
// instead of one per fragment.
varying flat float v_drain;

// ============================================================================
// FIVE BURN CHARACTERS — THE CANONICAL DEFINITION. Everything else that names them
// (`tools/TOOL_gen_burn_maps.py`'s CHARACTERS, docs/DOC_burnt_vegetation.md's table) is a
// mirror of these three rows and has to be changed with them. Pin one with the
// `burn_character` uniform above; look at all five side by side with
// `python3 tools/TOOL_gen_burn_maps.py --preview <dir>`, which writes
// `burn_characters.png`.
// ============================================================================
//
// PICKED PER PLANT, so a hillside going up is not one effect
// applied five thousand times. A fire in a real stand is ragged because the fuel
// is: one tree goes up like a torch, the one beside it smoulders for an hour, a
// third burns as a seam creeping up one side. This is that, for nothing — the pick
// is a hash of the instance's own position, so it costs no per-instance buffer, no
// extra material and no second draw call, exactly like the sprite flip.
//
// RELATIVE, NOT ABSOLUTE. Each row scales or offsets the MATERIAL's own values
// rather than replacing them, so the four materials keep control of the overall
// look and these only say how far each plant departs from it. Multiply a class's
// `ember_energy` and all five of its characters move together.
//
//                     softness  energy  cooling
//   1  SHIPPED          x1.00     x1.00     —      the material's numbers, unchanged
//   2  TIGHT BAND       x0.45     x1.00     —      a narrow, definite seam creeping
//                                                  up one side of the plant
//   3  CROWN ALIGHT     x1.80     x1.00     —      most of the plant burning at
//                                                  once: the torch
//   4  HOT              x1.00     x2.00     —      same shape, twice the
//                                                  brightness, blooms hard
//   5  SMOULDERING      x1.00     x0.44   +0.10    barely alight, mostly char with
//                                                  red seams in it
//
// `burn_softness` is the interesting one: it is not only a look. It sets how much
// of a plant is mid-burn at any moment, so character 2 also reads as a QUICKER
// front than character 3 at the same `burn_rate`.
const float VAR_SOFTNESS[5] = float[](1.0, 0.45, 1.80, 1.0, 1.0);
const float VAR_ENERGY[5] = float[](1.0, 1.00, 1.00, 2.0, 0.44);
const float VAR_COOLING[5] = float[](0.0, 0.00, 0.00, 0.0, 0.10);

// Value noise for the burn patches. Same sin-hash the rest of the file uses, on a
// lattice, smoothstepped — cheap and good enough for blobs. It is deliberately NOT
// the baked fBm in the order channel: that field is fixed to the plant, and a patch
// that never moves is a stain rather than a fire.
float vhash(vec2 i) {
	return fract(sin(dot(i, vec2(12.9898, 78.233))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(vhash(i), vhash(i + vec2(1.0, 0.0)), f.x),
			mix(vhash(i + vec2(0.0, 1.0)), vhash(i + vec2(1.0, 1.0)), f.x), f.y);
}

// Flattened 4x4 Bayer matrix (matches the project's other dither shaders).
const float bayer[16] = float[](
	0.0, 8.0, 2.0, 10.0,
	12.0, 4.0, 14.0, 6.0,
	3.0, 11.0, 1.0, 9.0,
	15.0, 7.0, 13.0, 5.0);

float bayer4(vec2 fragcoord) {
	int x = int(mod(fragcoord.x, 4.0));
	int y = int(mod(fragcoord.y, 4.0));
	return bayer[x + y * 4] / 16.0;
}

// 0 or 1 from a world position. Only has to be arbitrary and stable — an instance
// must pick the same side every frame, and every vertex of an instance must pick
// the same side as its siblings, or the quad tears (see `v_flip`).
//
// QUANTISED TO A DECIMETRE FIRST, because `sin()` of an argument in the millions
// — which is what `dot()` on world coordinates a kilometre out produces — has
// almost no significant bits left in a 32-bit float. Two vertices a hair apart
// could otherwise hash to opposite sides. Snapping the input makes the hash a
// function of the instance's CELL rather than of its exact float coordinates, so
// it is stable against that and against a floating-origin rebase landing the same
// plant on a slightly different render-space position.
float flip_of(vec2 wp) {
	vec2 q = floor(wp * 10.0);
	return step(0.5, fract(sin(dot(q, vec2(12.9898, 78.233))) * 43758.5453));
}

// The continuous sibling of `flip_of`, on a different pair of constants: 0..1 from
// a world position, quantised to a decimetre first for the same reason and with
// the same guarantee — every vertex of an instance gets the same number, and the
// number survives a floating-origin rebase.
float hash01(vec2 wp) {
	vec2 q = floor(wp * 10.0);
	return fract(sin(dot(q, vec2(27.619, 57.583))) * 24634.6345);
}

// This instance's burn, from the bus (or the material's pin) and its own hash.
//
// THE FRONT, when `veg_burn_front.w` is positive, is a disc of burnt ground
// spreading from an origin: everything more than `burn_front_depth` inside the
// leading edge is through the fire, the last stretch behind the edge is still
// alight, and everything outside is untouched. `veg_burn` still gates it, so
// taking the bus back to 0 puts the fire out wherever it had got to.
//
// THE PER-INSTANCE SPREAD IS A LAG THAT CLOSES AT BOTH ENDS. Adding a flat
// +/- offset would leave plants alight in a field pinned to 0 and plants still
// green in one pinned to 1 — both of which are exactly the state the two extremes
// exist to rule out. Scaling it by 4a(1-a) is zero at 0 and at 1 and widest in the
// middle, which is also where a real fire's spread is most visible.
float burn_of(vec3 anchor, float seed, float patch) {
	float amount = burn >= 0.0 ? burn : veg_burn;
	if (veg_burn_front.w > 0.0) {
		float d = distance(anchor.xz, veg_burn_front.xz);
		amount *= clamp((veg_burn_front.w - d) / max(burn_front_depth, 0.001),
				0.0, 1.0);
	}
	// A BURN BAKED INTO THE INSTANCE by the scatter — the ring of forest a crash site
	// set alight, standing in an island the bus never lit. It raises THIS plant's
	// floor and no other's. `max`, not `+`: a plant on the crater lip is already
	// through the fire, and an island-wide burn laid on top of it is the SAME fire,
	// not a second one to drive it past cold. Zero on every plant away from a crash,
	// so this is a no-op across an ordinary island — and the lag below still spreads
	// the ring's edge plant by plant, since it closes at both ends of `amount`.
	amount = max(amount, patch);
	float lag = (seed - 0.5) * burn_variance * 4.0 * amount * (1.0 - amount);
	return clamp(amount + lag, 0.0, 1.0);
}

// The near term, guarded. `smoothstep` with equal edges is undefined, and the
// grass materials set both to zero to disable it, so the comparison is the
// switch rather than an optimisation.
//
// `shrink` PULLS THE WHOLE BAND IN AS A PLANT COLLAPSES, and it is the reason the
// `_stump` materials do not have to override the two figures by hand. The near fade
// is a TREE feature — it exists because a wood at a ~6.7 m spacing is a wall a metre
// from the eye, and everything shorter than the player switches it off. A stump is
// shorter than the player. Scaling rather than switching means the clearing closes
// as the crown comes down instead of vanishing the moment the collapse begins.
float fade_near(float d, float shrink) {
	float gone = near_gone * shrink;
	float solid = near_solid * shrink;
	return solid > gone ? smoothstep(gone, solid, d) : 1.0;
}

void vertex() {
	// The instance's own scale, taken off the model matrix before it is replaced.
	// Only the two axes the quad actually spans; the billboard supplies the third.
	float sx = length(MODEL_MATRIX[0].xyz);
	float sy = length(MODEL_MATRIX[1].xyz);

	// the lo-fi grid: this plant's size in metres times the texels a metre,
	// never finer than the picture (see `lofi_texels_per_m`)
	vec2 tex_size = vec2(textureSize(albedo_tex, 0));
	v_cells = tex_size;
	if (lofi_texels_per_m > 0.0) {
		vec2 world = vec2(sx * quad_size.x, sy * quad_size.y);
		v_cells = clamp(max(world * lofi_texels_per_m, vec2(lofi_min_texels)), vec2(1.0), tex_size);
	}

	vec3 up = vec3(0.0, 1.0, 0.0);
	vec3 right = INV_VIEW_MATRIX[0].xyz;
	right = normalize(right - up * dot(up, right));
	vec3 fwd = normalize(cross(right, up));

	mat4 m;
	m[0] = vec4(right * sx, 0.0);
	m[1] = vec4(up * sy, 0.0);
	m[2] = vec4(fwd * sx, 0.0);
	m[3] = MODEL_MATRIX[3];

	// THE INSTANCE'S ANCHOR, read before the sway moves anything. Everything that
	// has to be one value for the whole quad is derived from THIS and never from
	// `m[3]`, which the sway below makes per-vertex. Taking the flip off the swayed
	// origin is what tore the sprites; the wind phase gets it too, so a gust is a
	// property of where the plant stands rather than of which corner is asking.
	vec3 anchor = MODEL_MATRIX[3].xyz;

	// RESOLVED HERE, before anything reads it, because both the sway below and the
	// drain in fragment() have to agree about which side of the wall this plant is
	// on. `MODEL_MATRIX[3]` is render space, which is the frame the wall is
	// published in — see the include's header on the two frames.
	v_drain = golf_wall_outside(anchor.xz);

	// Sway, applied in the billboard's own right/forward plane and scaled by UV.y's
	// complement so the base stays planted. The phase is a function of the
	// instance's WORLD position, not of its index, so a gust reads as a wave
	// crossing the field rather than as every plant twitching independently.
	//
	// The clock is the WALL'S, not TIME: outside an engaged hole it stops at the
	// instant the wall went up, so a gust crossing the field runs into the boundary
	// and holds there. `mix`ed rather than damped, so the plants keep their lean
	// instead of straightening — see `golf_wall_time`.
	if (wind_strength > 0.0) {
		float wind_t = mix(TIME, golf_wall_fx.y, v_drain);
		float phase = (anchor.x + anchor.z) / max(wind_scale, 1e-3) + wind_t * wind_speed;
		float lean = (1.0 - UV.y) * wind_strength * sin(phase);
		m[3].xyz += (right * lean + fwd * lean * 0.5);
	}

	// THE SHAKE (at the user's request; game/veg_damage.gd): a plant that is
	// hit is thrown about for a moment, harder the nearer it is to coming
	// apart. INSTANCE_CUSTOM.z is `shake_clock` when it was hit, .w how hard
	// (m); a plant never hit has both 0 and is never thrown. A new throw
	// forty times a second, the top thrown furthest, dying away.
	float since = shake_clock - INSTANCE_CUSTOM.z;
	if (INSTANCE_CUSTOM.w > 0.0 && since >= 0.0 && since < 0.45) {
		float k = INSTANCE_CUSTOM.w * (1.0 - since / 0.45) * (0.35 + 0.65 * (1.0 - UV.y));
		float q = floor(since * 40.0);
		vec2 r = fract(sin(vec2(q * 12.9898 + anchor.x, q * 78.233 + anchor.z)) * 43758.5453) * 2.0 - 1.0;
		m[3].xyz += (right * r.x + fwd * r.y * 0.5) * k;
	}

	MODELVIEW_MATRIX = VIEW_MATRIX * m;
	// THE PLANT'S OWN DISTANCE, which is the near band's other measuring point.
	// Off the ANCHOR — the base of the quad, where `veg_scatter` stands it on the
	// ground (`center_offset` puts the geometry entirely above the origin) — so it
	// is the distance to where the plant IS rather than to whichever corner of it
	// the rasteriser happens to be filling. Taken pre-sway like everything else
	// here: a gust that moved this would breathe the whole clearing in and out.
	//
	// Computed unconditionally rather than under an `if (near_fade_whole_plant)`.
	// The uniform is constant across a whole draw so the branch would not diverge;
	// what it would save is one mat4 multiply standing beside the one the line
	// above already does, and what it would cost is a `v_near` left undefined on
	// the other path — a trap for the next thing that wants this number.
	v_near = length((VIEW_MATRIX * vec4(anchor, 1.0)).xyz);
	v_flip = flip_variants ? flip_of(anchor.xz) : 0.0;
	// Off the ANCHOR, like everything else that has to be one value for the whole
	// quad — not off `m[3]`, which the sway above has already made per-vertex.
	v_seed = hash01(anchor.xz);
	// INSTANCE_CUSTOM.x is the scatter's per-plant crater burn — a MultiMesh custom-
	// data channel (`SCRIPT_veg_scatter.gd`/`SCRIPT_grass_scatter.gd` both `use_custom_data`). A
	// mesh that sets none reads it as 0, which is exactly the no-op an ordinary plant
	// wants, so nothing outside a crash site has to opt out.
	v_burn = burn_of(anchor, v_seed, clamp(INSTANCE_CUSTOM.x, 0.0, 1.0));
	// A SECOND, INDEPENDENT hash — off the same anchor but different constants, so
	// which character a plant has is uncorrelated with when it catches. Sharing
	// `v_seed` would make every torch in the wood also an early one.
	//
	// PINNED, if `burn_character` says so — 1..5 there means every plant is that
	// one, which is how a character gets looked at on its own. The uniform is
	// 1-based and the arrays are 0-based, and that subtraction is the only place
	// the two conventions meet.
	int vi = burn_character >= 1
			? clamp(burn_character - 1, 0, 4)
			: int(min(floor(hash01(anchor.xz + vec2(5.7, 13.1)) * 5.0), 4.0));
	float spread = burn_character >= 1 ? 1.0 : burn_variety;
	v_char = mix(vec3(1.0, 1.0, 0.0),
			vec3(VAR_SOFTNESS[vi], VAR_ENERGY[vi], VAR_COOLING[vi]), spread);
	// Gated by the burn, so a forest the fire never reached does not fall over when
	// the stump bus moves. Also per-instance through `v_burn`, which carries the
	// spread — the plants that caught first are the first to come down.
	v_stump = clamp((stump >= 0.0 ? stump : veg_stump) * v_burn, 0.0, 1.0);
}

void fragment() {
	// THIS PLANT'S CLOCK, resolved once. Every animated term below runs on it
	// rather than on TIME, so a plant outside an engaged hole's wall holds still in
	// every respect — not just its sway. The embers were the reason this is here
	// and not only in vertex(): a burning wood left flickering inside a stopped
	// world is exactly the tell the wall exists to remove.
	float wall_t = mix(TIME, golf_wall_fx.y, v_drain);
	// Mirrored on the U axis only. The sprites are cutouts of real plants, so a
	// mirror is as valid a plant as the original; flipping V would stand it on
	// its head.
	vec2 uv = vec2(mix(UV.x, 1.0 - UV.x, v_flip), UV.y);
	// (how many texels one pixel covers, as log2: nearest at one to one and
	// under, filtered from two up — see `albedo_smooth`)
	vec2 duvx = dFdx(uv);
	vec2 duvy = dFdy(uv);
	vec2 foot = max(abs(duvx), abs(duvy)) * vec2(textureSize(albedo_tex, 0));
	float minified = clamp(log2(max(max(foot.x, foot.y), 1e-6)), 0.0, 1.0);
	// THE LO-FI GRID: the picture read at the middle of its cell on the
	// coarser grid (`v_cells`), the mip chosen off the real footprint
	// (a snapped coordinate has no gradient of its own)
	uv = (floor(uv * v_cells) + 0.5) / v_cells;
	// (the sharp fetch off the full picture only, as the standees: an
	// Intel iGPU picks its mip differently and flips it along an edge)
	vec4 tex = mix(textureLod(albedo_tex, uv, 0.0), textureGrad(albedo_smooth, uv, duvx, duvy), minified);
	if (tex.a < alpha_scissor) {
		discard;
	}

	// VERTEX is view-space (the billboard writes MODELVIEW_MATRIX), so its length
	// is the true 3D distance to the camera — the quantity the far fade and the
	// fog are defined against, and the default one for the near fade too.
	float d = length(VERTEX);
	// AND THE NEAR BAND MAY BE MEASURED SOMEWHERE ELSE. `d` is this FRAGMENT's
	// distance, `v_near` is the whole PLANT's, and `near_fade_whole_plant` picks
	// between them — the one place in this shader where the two differ. The far
	// band and the fog below stay on `d` unconditionally: both are properties of
	// how far through the air you are looking, which really is a per-fragment
	// question, and at 680 m a tree's own 22 m is inside the dither's noise anyway.
	float near_d = near_fade_whole_plant ? v_near : d;
	float vis = fade_near(near_d, 1.0 - v_stump * 0.9)
			* (1.0 - smoothstep(far_start, far_end, d));
	if (bayer4(FRAGCOORD.xy) >= vis) {
		discard;
	}

	vec3 col = tex.rgb;
	float ember = 0.0;
	vec3 ember_hue = vec3(1.0);

	// THE BURN, skipped entirely on an instance the fire has not reached — which is
	// every instance in the scene as shipped, so the whole block costs one `flat`
	// compare until something turns it on.
	if (v_burn > 0.0) {
		vec4 bm = textureGrad(burn_map, uv, duvx, duvy);

		// Sweep the order field. The remap is what makes the two ends absolute:
		// pushed out by `soft` at both, so `v_burn` = 1 drives even the
		// LAST texel (order 1) past the top of its band and `v_burn` = 0 leaves
		// even the first one below the bottom of its own.
		float soft = clamp(burn_softness * v_char.x, 0.02, 0.5);
		float a = v_burn * (1.0 + 2.0 * soft) - soft;
		float t = smoothstep(bm.b - soft, bm.b + soft, a);

		// THE BREAK. Everything above the line is gone; the line descends from just
		// clear of the quad's top to `stump_height` as the collapse completes, and
		// wanders by the baked foliage field so a trunk snaps where it is weak.
		//
		// Starting the line ABOVE 1.0 matters: a plant whose art does not reach the
		// top of its own quad (every bush and fern here — see `stump_height`) must
		// not have its crown taken off the instant the bus leaves zero, and 1.03 is
		// the margin that keeps the first frame of the collapse a no-op on the class
		// that DOES fill its quad.
		float above = 1.0 - uv.y;
		// The wander reaches full strength EARLY — a quarter of the way in — rather
		// than growing with the collapse. Scaled by `v_stump` it is 2 px at the
		// halfway point, which is a flat cut through a dense crown and reads as a
		// clipped hedge; the break wants to be uneven from the moment there is one.
		float wander = (0.5 - bm.a) * stump_ragged;
		// AND IT DROPS FOUR TIMES AS FAR AS IT LIFTS. The lift is what makes the
		// trunk stand proud of its break, and it is also what strands the odd
		// low-ash branch-tip texel in mid-air above the stump — nothing in a
		// fragment shader knows whether a texel is attached to anything, so a lift
		// applied out at the tips leaves flies over the stub. Capping the up half
		// keeps the splinter and loses them.
		wander *= wander > 0.0 ? 0.25 : 1.0;
		float line = mix(1.03, stump_height, v_stump)
				+ wander * min(v_stump * 4.0, 1.0);
		if (above > line) {
			discard;
		}

		// The art's own luminance, carried through both late stages as a
		// MULTIPLIER on the char and the ash. Mixing to a flat colour instead
		// floods the silhouette and throws away the branch shadows and the lit
		// side of the crown — a burnt tree is still a tree with a light side.
		float lum = dot(tex.rgb, vec3(0.2126, 0.7152, 0.0722));

		// Dry and brown, then black, then a little ash on what is left. The three
		// bands overlap deliberately: a plant is scorching at its crown while its
		// lower branches are already charring.
		col = mix(col, col * 0.55 + scorch_color, smoothstep(0.0, 0.55, t) * 0.85);
		col = mix(col, char_color * (0.55 + 2.6 * lum),
				smoothstep(0.30, 0.95, t) * bm.g);
		col = mix(col, ash_color * (0.60 + 2.0 * lum),
				smoothstep(0.85, 1.0, t) * (1.0 - bm.g) * 0.55);

		// WEATHERING. A stump is not fresh char — it has had a year of rain on it,
		// and bleached grey wood is what separates an old burn scar from a new one.
		// It also lifts the silhouette off the terrain, which matters: cold char
		// alone sits at about a third of the ground's luma in this scene and a
		// stump is small enough to disappear into it.
		col = mix(col, ash_color * (0.50 + 1.6 * lum), v_stump * 0.35);

		// The broken end reads PALE — raw splintered wood and ash sitting on top of
		// the char, which is the one thing that tells a stump from a post. A couple
		// of texels deep, so it is a rim and not a cap.
		col = mix(col, ash_color * 1.15,
				(1.0 - smoothstep(0.0, 0.03, line - above)) * v_stump * 0.7);

		// Two sines beaten against each other rather than one, so neighbouring
		// coals on the same plant are not in step; the instance seed keeps two
		// plants from being either.
		float flick = 0.80 + 0.30
				* sin(wall_t * ember_speed + v_seed * 31.4 + uv.y * 17.0)
				* sin(wall_t * ember_speed * 0.41 + v_seed * 12.0 + uv.x * 23.0);
		// The flame is a narrow band travelling with the front; the coals are what
		// it leaves behind, and they cool.
		float q = (t - 0.5) / 0.16;
		float flame = exp(-q * q);

		// The patches, drifting over whatever the sweep has already left behind.
		// Offset per instance so two plants side by side are not alight in the same
		// places, and biased onto the CHAR field so a patch lands where there was
		// fine fuel rather than floating over a bare trunk.
		float patch = 0.0;
		if (burn_patches > 0.0) {
			vec2 pp = uv * patch_scale + vec2(v_seed * 37.0, v_seed * 11.0);
			float n = vnoise(pp + vec2(wall_t * patch_speed * 0.21,
					-wall_t * patch_speed)) * 0.65
					+ vnoise(pp * 2.3 - vec2(wall_t * patch_speed * 0.5,
							wall_t * patch_speed * 0.31)) * 0.35;
			float cut = 1.0 - burn_patches;
			patch = smoothstep(cut, cut + 0.12, n) * mix(0.55, 1.0, bm.g);
			// AND THROUGH THE PLANT'S OWN TEXTURE. Without this the patch is a
			// smooth blob laid over the silhouette — it reads as orange paint,
			// because a noise field knows nothing about where the needles are. The
			// art's own luminance is exactly that map: lit foliage takes the fire
			// and the gaps between it stay black, so the patch acquires the
			// plant's structure instead of hiding it.
			patch *= 0.35 + 0.65 * smoothstep(0.02, 0.22, lum);
		}
		float cooling = clamp(ember_cooling + v_char.z, 0.0, 1.0);
		float energy = ember_energy * v_char.y;
		float coal = bm.r * smoothstep(0.30, 0.62, t)
				* (1.0 - cooling * smoothstep(0.70, 1.0, t));
		// The patch is added rather than maxed in: a patch that happens to land on
		// the sweep's own flame front should be the brightest thing on the plant.
		ember = (flame * (0.22 + 0.78 * bm.r) + coal + patch * 0.85) * flick * energy;

		// The palette cycle — see the uniform block. Read the ramp's length off the
		// texture rather than off a uniform so the two cannot disagree; unbound it
		// is 1x1 and the guard leaves every lookup on the single (white) texel.
		int steps = textureSize(ember_ramp, 0).x;
		float span = float(max(steps - 1, 1));
		// WHERE a texel sits in the ramp is the FRONT plus a little of the coals
		// behind it — deliberately not `ember`, which is the same thing multiplied
		// by the baked ember SPECKLE. Indexing the ramp by the quantity that already
		// sets the intensity squares the speckle, and the plant comes out covered in
		// individually-coloured sparks instead of carrying a band of flame. It is
		// also independent of `ember_energy`, so a material that dims its fire dims
		// it rather than recolouring it.
		float heat = clamp(flame * 0.62 + coal * 0.45 + patch * 0.70, 0.0, 1.0);
		// Phase runs AGAINST the burn order, so a feature climbs as the clock advances.
		// The seed keeps two plants out of step; the ember field keeps two coals on
		// the same plant out of step.
		float ph = wall_t * ember_cycle_speed - bm.b * ember_cycle_climb
				+ v_seed * 3.7 + bm.r * 1.3;
		float wave = abs(fract(ph) * 2.0 - 1.0) - 0.5;
		// Scoped to the flame. Settled coals shimmer at a third of the swing and
		// cold char does not move.
		float swing = ember_cycle_depth * (0.35 + 0.65 * flame);
		float idx = clamp(heat + wave * 2.0 * swing, 0.0, 1.0);
		// Quantise to a whole step BEFORE the lookup. This is the difference between
		// indexed colour flipping and a gradient sliding.
		ember_hue = texture(ember_ramp,
				vec2((floor(idx * span) + 0.5) / float(steps), 0.5)).rgb;
	}

	// `tint` is the material's own, authored per plant class; `tod_art_tint` is the
	// scene's, and it is the whole of what nightfall does to a plant here. Before
	// the haze, deliberately and for the same reason the fog mix is after the light
	// on the terrain: the tint is the light falling ON the leaf, the haze is the air
	// between the leaf and the eye, and they compose in that order.
	ALBEDO = col * tint * tod_art_tint.rgb;

	float haze = 0.0;
	if (fog_enabled) {
		float fd = max(d - fog_distance_start, 0.0) * fog_distance_density;
		haze = 1.0 - exp(-pow(fd, fog_distance_power));
		// Unshaded, so the haze is a straight mix toward the fog colour rather
		// than the darken-plus-EMISSION dance a lit shader needs to survive its
		// own light term.
		ALBEDO = mix(ALBEDO, fog_color * tod_haze_tint.rgb, haze);
	}

	// AFTER the fog, and dimmed by it rather than mixed into it — see the header.
	// This is also the only value in the shader allowed over 1.0, which is what
	// makes the environment's glow bloom it.
	if (ember > 0.0) {
		ALBEDO += ember_hue * ember_color * ember * mix(1.0, 0.3, haze);
	}

	// LAST, AND AFTER THE EMBER ON PURPOSE. The ember is the one value in this
	// shader allowed over 1.0, and draining it is what stops a stopped wood from
	// glowing orange in a grey world. Letting it through would have read as the
	// fire being exempt from the wall rather than as an accent.
	//
	// `golf_wall_grade` AND NOT AN INLINE MIX. This used to compute its own luma
	// here, because the masked `golf_wall_drain` wants a world XZ and this shader
	// resolves its mask per instance instead. That copy was silently a third
	// implementation of the grade, and it stopped agreeing with the other two the
	// moment the sepia tone was added — every plant in the world stayed grey while
	// the ground under it went brown. The shared entry point takes the mask as a
	// number for exactly this case.
	//
	// `v_drain` rather than a fresh `golf_wall_outside` call: the vertex stage
	// already answered this for the whole quad, and asking again per fragment would
	// both cost more and let the two stages disagree at a boundary.
	ALBEDO = golf_wall_grade(ALBEDO, v_drain, SCREEN_UV, TIME);
	// THE THERMAL SIGHT's feed (godot/shaders/thermal_base.gdshaderinc):
	// only people are hot, and this is not one
	if (thermal_on(VIEWPORT_SIZE)) ALBEDO = thermal_out(thermal_cold(ALBEDO, clamp((length(VERTEX) - 700.0) / 2500.0, 0.0, 1.0)));
}
