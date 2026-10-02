## MEWD — what is left of the people (js/people.js Giblets).
##
## A shopper has twelve health, which is under one tic of the stream, so
## touching one with the flame is the same as deciding to; and there is
## no death animation because there is no body. There is a fireball,
## thirteen pieces of somebody thrown outward on fire, a trail of flame
## behind each, and a pool of blood where they stood and a splat where
## each piece lands.
##
## THE BUDGET, because a crowd of a hundred and twenty could otherwise
## put a thousand particles in the air at once: pools, sized so that nine
## or ten people can be coming apart simultaneously and the eleventh
## simply gets fewer pieces. Each pool is one draw. What is left on the
## floor is capped too — the pools of blood by the decals' own ring, the
## heaps of ash by GIB.maxSplats — or a night of this would leave a
## thousand sprites lying about.
##
## Wiring (see the parent's game.gd): Giblets.new(game) added as a child;
## tic() once a tic, draw() once a frame. It reads game.fx (Effects) and
## game.gore_decals (GoreDecals) if they are there, and runs without them.
class_name Giblets
extends Node3D

## the gore strip: eleven pieces of somebody in 16x16 cells
const GIBLETS := 11
const ASHES := 3
const ASH_CELL := Vector2(40, 18)

const GIB := {
	"count": 13,          # pieces of a person
	# Thrown HARD and wide. The first pass at these numbers dropped
	# everything in a two-metre circle, which reads as a person falling
	# over rather than a person going off: at eight units a tic with very
	# little drag a piece clears sixty or seventy before it lands, so the
	# thirteen of them end up spread across an aisle and over the shelf
	# into the next one.
	"speedMin": 1.8, "speedMax": 8.0,
	"riseMin": 3.0, "riseMax": 8.5,
	"gravity": -0.5,
	"drag": 0.985,
	"lifeMin": 55, "lifeMax": 110,
	"sizeMin": 9.0, "sizeMax": 15.0,
	"trailEvery": 2,      # tics between flames off a piece in the air
	"splatChance": 90,    # out of 255, per piece that lands
	"maxSplats": 140,     # heaps left lying about before the oldest goes
}

## AND BLOWN APART, which is a different thing from coming apart. At the
## user's request: "i also want people to literally explode into viscera
## and gore chunks when hit by a rocket in a more extreme way". A rocket
## kill is the burst AND THEN THIS, on top of it: many more pieces, not
## on fire, trailing blood; thrown AWAY from the blast in a cone, faster
## and higher than any burst; a spray of blood in the air; and the room
## painted — a great pool where they stood, spatters thrown across the
## floor round it, and blood up every wall in reach.
##   count  pieces;  speed/rise  units a tic, before `force`;  cone  radians
##   either side of the throw;  spray  blood particles in the air;  floor
##   spatters across the floor, and how far;  walls  rays to the walls, and
##   how far;  pool  the size of the pool under them
## the room's blood, waiting to go down (eviscerate, _room_tic)
const ROOM_FLOOR := 0
const ROOM_WALLS := 1
const ROOM_RAYS := 5
const ROOM_PER_TIC := 40
var room: Array = []

const GORE := {
	"count": 60,
	"speedMin": 4.0, "speedMax": 15.0,
	"riseMin": 5.0, "riseMax": 15.0,
	"cone": 1.9,
	"sizeMin": 7.0, "sizeMax": 17.0,
	"lifeMin": 70, "lifeMax": 150,
	"gravity": -0.55,
	"drag": 0.988,
	"spray": 90,
	"floor": 12, "floorReach": 190.0,
	"walls": 20, "wallReach": 360.0,
	"pool": 118.0,
	"trailEvery": 3,      # tics between blood off a piece in the air
}
## the wet dark ones, which is the tint that says viscera rather than
## meat — multiplied onto the gore art the way the frozen one is
const WET_GIB := Color(0.78, 0.55, 0.55)
## What a piece of somebody frozen is coloured: red barely moves, green
## and blue lift hard, and dark red meat comes out the pale grey-pink of
## something out of a freezer. A lighting decision, not a repaint.
const FROZEN_GIB := Color(1.0, 1.45, 1.85)

## IT USED TO LIGHT THE FLOOR WHERE IT LANDED, and in the JS that was
## the single biggest reason the store burnt down without the player:
## thirteen pieces thrown seventy units in every direction is thirteen
## new fires in a ring round the body, and one shopper going off in a
## crowd started a chain across the shop. It was the best-looking
## mechanic in the game and also an automatic win, so the JS turned it
## off (people.js _land). Kept here as a switch, off, for whoever wants
## to see it again: each burning piece that lands puts this much heat
## into the fire grid.
const LIGHT_FLOOR := false
const LAND_HEAT := 40.0

const UP := Vector3(0, 0, 1)

## what each chunk slot is: 0 a burning piece, 1 off a drilled head
## (never alight), 2 viscera off a warhead (trails blood)
enum { K_BURN, K_SPURT, K_GORE, K_BORE }

## THE REMAINS, at the user's request ("lots of random body parts lying
## around for a while"): a piece of somebody that lands on the floor stays
## there as the part it is (giblets.png: meat, a foot, a hand, an eye,
## guts, ribs, a heart, a brain), standing on its little card like a
## person does, for REMAINS_TICS, shrinking into the floor over the last
## REMAINS_FADE, the oldest going first past REMAINS_MAX. Every piece the
## cerebral bore throws stays; one in REMAINS_GORE_EVERY of a warhead's.
const REMAINS_MAX := 900
const REMAINS_TICS := 60 * 35
const REMAINS_FADE := 4 * 35
const REMAINS_GORE_EVERY := 3
## THE BORE'S FINISH (bore_explode), at the user's request: "an absurd
## amount of gore and viscera" — the head goes first and the rest after
## it, far more of everything than a warhead throws, and the neck keeps
## going for a while after
const BORE_GORE := {"parts": 90, "speedMin": 3.0, "speedMax": 13.0, "riseMin": 8.0, "riseMax": 22.0,
	"sizeMin": 10.0, "sizeMax": 22.0, "spray": 260, "pools": 5, "fountainTics": 105, "force": 2.2}
## the head's own parts, weighted: the brain, the eyes, the teeth, then
## any part at all
const HEAD_PARTS := [10, 10, 10, 5, 5, 5, 4, 4, 9, 9, 6, 6, 0, 1, 2, 3, 7, 8]

var game
var chunks: Particles
var trail: Particles
var shards: Particles
var chunk_kind := PackedByteArray()
## THE CHECKS, every other tic (for speed: five hundred pieces in the air
## after a rocket into a crowd, each casting a ray and asking for its
## floor every tic, was a third of an old laptop's frame): where each
## piece was last checked against the walls — the ray goes from there,
## two tics of flight, so nothing slips through — and the floor under it
## then (UNKNOWN until its first check)
var chk_x := PackedFloat32Array()
var chk_y := PackedFloat32Array()
var chk_z := PackedFloat32Array()
var chunk_floor := PackedFloat32Array()
const UNKNOWN := -1.0e9
var tics := 0
## counts, for the tests
var pools := 0
var bursts := 0
var shatters := 0
var ashes := 0
var eviscerations := 0

## the heaps of ash, drawn as standees from a strip baked here: [x, y, z, variant]
var ash_piles: Array = []
## [x, y, z, frame, size, born (tic), mirrored, light, sky]
var remains: Array = []
var _rem_mm: MultiMesh
var _rem_dirty := false
var _rem_buf := PackedFloat32Array()
## the necks still going: {x, y, z, tics}
var fountains: Array = []
var bore_finishes := 0
var _ash_mm: MultiMesh
var _ash_dirty := false

func _init(g) -> void:
	game = g
	var art: Texture2D = load("res://assets/people/giblets.png")
	# The pieces themselves: cut-out art, lit by the room like anything
	# else, so a hand landing in a dark aisle is dark. Seven hundred and
	# twenty since the warhead: one kill by it is sixty pieces, and a
	# salvo of four through a queue is four of those at once.
	chunks = Particles.new({"max": 720, "map": art, "frames": GIBLETS, "blend": "mix", "fullbright": false,
		"near_shrink": 80.0, "order": 13})
	chunks.mat.set_shader_parameter("light", U.col(0.9))
	chunk_kind.resize(chunks.max)
	for arr in [chk_x, chk_y, chk_z, chunk_floor]:
		arr.resize(chunks.max)
	# And the fire coming off them: the same fireballs the gun fires,
	# small, additive, gone in a third of a second, which is what turns
	# thirteen tumbling objects into thirteen comets.
	trail = Particles.new({"max": 300, "map": Effects.atlases().fireball, "frames": Effects.FIREBALLS, "blend": "add",
		"fullbright": true, "near_shrink": 30.0, "order": 11})
	# AND A SECOND POOL FOR THE COLD ONES, which is not tidiness — it is
	# the bug that shipped for ten minutes in the JS, when shattering a
	# frozen shopper set the beans aisle on fire. Same art, same
	# ballistics; what they ARE is the difference, so a different pool
	# with a different tic.
	shards = Particles.new({"max": 200, "map": art, "frames": GIBLETS, "blend": "mix", "fullbright": false,
		"near_shrink": 80.0, "order": 13})
	shards.mat.set_shader_parameter("light", U.col(1.0))
	for p in [chunks, shards, trail]:
		add_child(p)
	_make_ash_batch()
	_make_remains_batch()

func _fx():
	return game.get("fx")

func _decals():
	return game.get("gore_decals")

static func _r() -> float:
	return U.p_random() / 255.0

func _height(a) -> float:
	return a.height if a.height > 8.0 else 56.0

# ------------------------------------------------------------------
# The burst
# ------------------------------------------------------------------

## Somebody is no longer a person. `a` is the actor it happened to — in
## the Godot port they are already dead, so their height has dropped to
## eight: the pieces come off the height they stood at.
func burst(a) -> void:
	bursts += 1
	game.play_sound("gib", a)
	# The fireball, standing on the floor where they were. It is an actor
	# and not a particle because a particle is square and this is twice
	# as tall as it is wide.
	game.spawn("BLAST", a.x, a.y)
	# A pool under them straight away, so there is something there even
	# if every piece flies off somewhere else.
	splat(a.x, a.y, a.z)
	# AND EVERYBODY WHO SAW IT LEAVES. This is the loudest thing that
	# happens in the game and it happens to a person, so it clears a much
	# wider circle than the fire does: torch one at the tills and the
	# whole front end is running before the pieces land.
	game.scare(a.x, a.y, 900.0)
	var h := _stood(a)
	for k in GIB.count:
		var ang := _r() * TAU
		var sp: float = GIB.speedMin + _r() * (GIB.speedMax - GIB.speedMin)
		var size: float = GIB.sizeMin + _r() * (GIB.sizeMax - GIB.sizeMin)
		_chunk({
			"x": a.x, "y": a.y, "z": a.z + h * (0.25 + _r() * 0.6),
			"vx": cos(ang) * sp, "vy": sin(ang) * sp, "vz": GIB.riseMin + _r() * (GIB.riseMax - GIB.riseMin),
			"life": GIB.lifeMin + (U.p_random() % (GIB.lifeMax - GIB.lifeMin)),
			"size0": size, "c0": Color.WHITE,
			"frame": float(U.p_random() % GIBLETS),
			"drag": GIB.drag, "gravity": GIB.gravity,
		}, K_BURN)

## the height somebody stood at: Actor.die drops `height` to eight, so
## the type's own is the one wanted
func _stood(a) -> float:
	var h: float = float(a.info.get("height", a.height)) if a.get("info") != null else float(a.height)
	return h if h > 8.0 else 56.0

func _chunk(o: Dictionary, kind: int) -> int:
	var i := chunks.spawn(o)
	if i >= 0:
		chunk_kind[i] = kind
		chk_x[i] = chunks.px[i]
		chk_y[i] = chunks.py[i]
		chk_z[i] = chunks.pz[i]
		chunk_floor[i] = UNKNOWN
	return i

# ------------------------------------------------------------------
# BLOWN APART BY A WARHEAD — see GORE for what and why. `a` is who, `at`
# (map-space Vector3, or null) is where the warhead went off, `force`
# scales the whole throw: one for a body in the blast, more for the one
# it went off IN. Nothing for a thing that does not bleed. Returns how
# many marks it left on the room.
# ------------------------------------------------------------------
## `share`: how much of a whole body's worth this one gets — a rocket into
## a crowd shares one budget among everybody it kills (MissileSystem.
## detonate: one over the square root of how many), so one body is as
## extreme as ever and eight are about three bodies' worth of pieces, not
## eight: eight was fifteen hundred things flying at once, each asking
## the walls and the floor where it was, and the handheld stopped.
func eviscerate(a, at = null, force := 1.0, share := 1.0) -> int:
	if a == null or a.get("vehicle") or a.frozen:
		return 0
	share = clampf(share, 0.05, 1.0)
	eviscerations += 1
	game.play_sound("gib", a)
	var h := _stood(a)
	var mid: float = a.z + h * 0.5
	# which way the body goes: away from the blast, and up with it if the
	# blast was under them
	var dx: float = a.x - at.x if at != null else 0.0
	var dy: float = a.y - at.y if at != null else 0.0
	var dz: float = maxf(0.0, mid - at.z) if at != null else 0.0
	var dl := sqrt(dx * dx + dy * dy)
	var has_dir := dl > 1.0
	var dir := atan2(dy, dx) if has_dir else 0.0
	if has_dir:
		dx /= dl
		dy /= dl
	else:
		dx = 0.0
		dy = 0.0
	# THE PIECES
	for k in maxi(6, roundi(GORE.count * share)):
		var spin := _r() * TAU
		var ang: float = dir + ((U.p_random() / 128.0) - 1.0) * GORE.cone if has_dir else spin
		var sp: float = (GORE.speedMin + _r() * (GORE.speedMax - GORE.speedMin)) * force
		var size: float = GORE.sizeMin + _r() * (GORE.sizeMax - GORE.sizeMin)
		# (put, not spawn: the same fields in the same order, no Dictionary)
		var z: float = a.z + 4.0 + _r() * h * 0.9
		var vz: float = (GORE.riseMin + _r() * (GORE.riseMax - GORE.riseMin)) * (0.8 + 0.2 * force) + dz * 0.02
		var life: float = GORE.lifeMin + (U.p_random() % (GORE.lifeMax - GORE.lifeMin))
		var c: Color = WET_GIB if (k & 1) == 0 else Color.WHITE
		var i := chunks.put(a.x, a.y, z, cos(ang) * sp, sin(ang) * sp, vz, life, size, size, c, c,
			float(U.p_random() % GIBLETS), 0.0, GORE.drag, GORE.gravity)
		if i >= 0:
			chunk_kind[i] = K_GORE
			chk_x[i] = a.x
			chk_y[i] = a.y
			chk_z[i] = z
			chunk_floor[i] = UNKNOWN
	# THE SPRAY, in the air: half of it thrown with the pieces and half
	# of it every way at once
	var fx = _fx()
	if fx != null:
		var spray := maxi(8, roundi((GORE.spray >> 1) * share))
		fx.blood_spray(a.x, a.y, mid, dx, dy, 0.4, spray, 1.2 * force)
		fx.blood_spray(a.x, a.y, mid, 0.0, 0.0, 0.0, spray, 0.9 * force)
		for k in maxi(2, roundi(6 * share)):
			fx.blood_puff(a.x, a.y, mid + (k - 3) * 6.0)
	# AND THE ROOM. The pool where they stood, bigger than any other in
	# the game; the spatters across the floor, thrown out the way the
	# pieces went; and blood up every wall round them. Their dice are
	# thrown now (the simulation's random numbers go as they always did);
	# the rays and the marks wait in `room` and go down ROOM_PER_TIC a
	# tic — a rocket into a crowd is ten of these at once, three hundred
	# marks and as many rays, which on an old laptop was a fifth of a
	# second in one frame. Spread over the next few tics, as the blood
	# flies, nobody sees it arrive late.
	var D = _decals()
	var marks := 0
	if D != null:
		var floor: float = a.z
		splat(a.x, a.y, floor, GORE.pool * (0.85 + 0.3 * _r()))
		marks += 1
		for k in maxi(3, roundi(GORE.floor * share)):
			var ang: float = _r() * TAU if (not has_dir or (k & 3) == 3) else dir + ((U.p_random() / 128.0) - 1.0) * GORE.cone
			var d: float = 20.0 + _r() * GORE.floorReach
			room.append([ROOM_FLOOR, a.x, a.y, floor, cos(ang), sin(ang), d, 34.0 + _r() * 50.0])
			marks += 1
		var from := Vector3(a.x, a.y, mid)
		var u := Vector3(dx if has_dir else 1.0, dy, 0.05)
		var walls := maxi(ROOM_RAYS, roundi(GORE.walls * share))
		for k in range(0, walls, ROOM_RAYS):
			room.append([ROOM_WALLS, from, u, k, mini(ROOM_RAYS, walls - k)])
		marks += walls
	return marks

## THE ROOM'S BLOOD, waiting (eviscerate): ROOM_PER_TIC of it down a tic,
## the oldest first. A floor spatter is one ray and one mark; a run of
## wall spray is ROOM_RAYS of each.
func _room_tic() -> void:
	var D = _decals()
	if D == null:
		room.clear()
		return
	var lv: Level = game.level
	var budget := ROOM_PER_TIC
	var n := 0
	while n < room.size() and budget > 0:
		var j: Array = room[n]
		n += 1
		if j[0] == ROOM_FLOOR:
			var x: float = j[1]
			var y: float = j[2]
			var floor: float = j[3]
			var c: float = j[4]
			var s: float = j[5]
			var d: float = j[6]
			# only as far as the floor goes: a spatter on the far side of a
			# wall is a spatter through it
			var wall := lv.ray_hit_wall(x, y, floor + 4.0, x + c * d, y + s * d, floor + 4.0)
			var far: float = maxf(0.0, float(wall.t) * d - 6.0) if not wall.is_empty() else d
			D.blood(Vector3(x + c * far, y + s * far, floor), UP, Vector3(c, s, 0), j[7])
			budget -= 1
		else:
			D.spray_walls(j[1], j[2], j[4], GORE.wallReach, PI, 1.5, j[3])
			budget -= j[4]
	room = room.slice(n)

# ------------------------------------------------------------------
# AND THE COLD VERSION OF THE SAME THING
#
# NO FIREBALL AND NO SCARE. A burst is an explosion; shattering is
# quiet: a crack and a scatter, and the shopper four feet away carries
# on looking at the beans. That is the mechanic: a player who wants to
# clear an aisle without a stampede has a way to do it, and it is the
# only way there is. THE PIECES GO FURTHER AND DROP HARDER, because they
# are ice: no rise to speak of, more sideways, and they skitter.
#
# `blow`: {dx, dy, force} — which way it was swung, if anything said. A
# blow with a direction throws the pieces along it inside a WIDE cone
# (±60°: a block of ice hit with a hammer comes apart mostly forwards,
# not as a beam); without one, a ring. `force` 1 is a shove; three is a
# swing that puts somebody through the freezer aisle.
# ------------------------------------------------------------------
func shatter(a, blow := {}) -> void:
	shatters += 1
	game.play_sound("shatter", a)
	splat(a.x, a.y, a.z)
	var bdx: float = blow.get("dx", 0.0)
	var bdy: float = blow.get("dy", 0.0)
	var has_dir := bdx != 0.0 or bdy != 0.0
	var dir := atan2(bdy, bdx)
	const CONE := 1.05
	var force := maxf(0.2, float(blow.get("force", 1.0)))
	var h := _stood(a)
	for k in GIB.count + 4:
		var spin := _r() * TAU
		var ang: float = dir + ((U.p_random() / 128.0) - 1.0) * CONE if has_dir else spin
		var sp: float = (GIB.speedMin + _r() * (GIB.speedMax - GIB.speedMin) * 1.25) * force
		var size: float = GIB.sizeMin * 0.7 + _r() * (GIB.sizeMax - GIB.sizeMin)
		shards.spawn({
			"x": a.x, "y": a.y, "z": a.z + h * (0.15 + _r() * 0.7),
			"vx": cos(ang) * sp, "vy": sin(ang) * sp,
			"vz": GIB.riseMin * 0.35 + _r() * GIB.riseMax * 0.4,
			"life": GIB.lifeMin + (U.p_random() % (GIB.lifeMax - GIB.lifeMin)),
			"size0": size, "c0": FROZEN_GIB,
			"frame": float(U.p_random() % GIBLETS),
			"drag": GIB.drag, "gravity": GIB.gravity * 1.25,
		})
	# and a breath of it hanging where they stood
	var fx = _fx()
	if fx != null:
		fx.frost_puff(a.x, a.y, a.z + h * 0.5)

# ------------------------------------------------------------------
# WHAT COMES OUT OF A HEAD WITH A DRILL IN IT: one or two small pieces
# off the top of the head, thrown up and a little out, that come down
# over the next second and land as blood does. The same pieces at half
# the size and a fifth of the speed, so they read as a fountain and not
# a firework; K_SPURT tells the tic not to put fire on them.
# ------------------------------------------------------------------
func spurt(a, n := -1) -> void:
	if n < 0:
		n = 1 + (U.p_random() & 1)
	for k in n:
		var ang := _r() * TAU
		var sp := 0.4 + _r() * 1.6
		var size: float = GIB.sizeMin * 0.45 + _r() * 3.0
		_chunk({
			"x": a.x, "y": a.y, "z": a.z + a.height * 0.92,
			"vx": cos(ang) * sp, "vy": sin(ang) * sp, "vz": 2.2 + _r() * 3.8,
			"life": 30 + (U.p_random() % 30), "size0": size, "c0": Color.WHITE,
			"frame": float(U.p_random() % GIBLETS),
			"drag": 0.985, "gravity": GIB.gravity,
		}, K_SPURT)

## THE OTHER THING LEFT ON THE FLOOR: somebody who burned away where
## they stood leaves a HEAP, not a stain. Capped at GIB.maxSplats, the
## oldest going first — what a long night must not end in is a carpet of
## sprites. (The JS spawns an ASH actor; nothing about a heap needs to
## think, so here it is a row in a batch this node draws.)
func ash_pile(a) -> void:
	ashes += 1
	ash_piles.append([a.x, a.y, a.z + 1.0, U.p_random() % ASHES])
	while ash_piles.size() > GIB.maxSplats:
		ash_piles.pop_front()
	_ash_dirty = true

## What is left on the floor: A POOL OF BLOOD, and it is a decal rather
## than a flat sprite, at the user's request — a puddle that spreads over
## its first seconds and dries at the rim (GoreDecals.pool). Capped by
## the decals' own ring.
func splat(x: float, y: float, z: float, size := 0.0) -> int:
	pools += 1
	var D = _decals()
	return D.pool(x, y, z, size) if D != null else -1

# ------------------------------------------------------------------
# One tic
# ------------------------------------------------------------------

func tic() -> void:
	tics += 1
	if not fountains.is_empty():
		_fountains_tic()
	_remains_tic()
	if not room.is_empty():
		_room_tic()
	var lv: Level = game.level
	var C := chunks
	var odd := tics & 1
	C.tic(func(i: int, nx: float, ny: float, nz: float) -> bool:
		var floor: float = chunk_floor[i]
		# the walls and the floor, every other tic (see chk_x), or at once
		# for a piece not yet checked, or one coming down onto its floor
		if (i & 1) == odd or floor == UNKNOWN or nz <= floor + 1.0:
			var x: float = chk_x[i]
			var y: float = chk_y[i]
			var z: float = chk_z[i]
			# A piece that goes through the frozen aisle wall and lands in
			# the car park is funny exactly once.
			var wall := lv.ray_hit_wall(x, y, z, nx, ny, nz)
			# ON THE WALL IT HIT, facing the side it came from
			if not wall.is_empty():
				_land(Vector3(wall.x, wall.y, wall.z), chunk_kind[i], Decals.wall_normal(wall.line, x, y), C.vx[i], C.vy[i], int(C.frame[i]), C.size0[i])
				return true
			var sec := lv.span_at(nx, ny, minf(z, nz) if floor == UNKNOWN else z)
			floor = sec.floor if sec else 0.0
			chunk_floor[i] = floor
			chk_x[i] = nx
			chk_y[i] = ny
			chk_z[i] = nz
		if nz <= floor + 1.0:
			_land(Vector3(nx, ny, floor), chunk_kind[i], UP, C.vx[i], C.vy[i], int(C.frame[i]), C.size0[i])
			return true
		return false)
	# the flame off each piece still in the air — except the ones off a
	# drilled head, which were never alight
	if C.count > 0:
		var fx = _fx()
		for i in C.live:
			if not C.alive[i] or chunk_kind[i] == K_SPURT:
				continue
			# A PIECE OFF A WARHEAD TRAILS BLOOD, not fire: it was never
			# alight, it was blown out of somebody
			if chunk_kind[i] == K_GORE or chunk_kind[i] == K_BORE:
				if fx != null and (tics + i) % GORE.trailEvery == 0 and (i & 1) == 0:
					fx.blood_spray(C.px[i], C.py[i], C.pz[i], -C.vx[i], -C.vy[i], 0.0, 1, 0.15)
				continue
			if (tics + i) % GIB.trailEvery:
				continue
			trail.spawn({
				"x": C.px[i], "y": C.py[i], "z": C.pz[i],
				"vx": C.vx[i] * 0.3, "vy": C.vy[i] * 0.3, "vz": C.vz[i] * 0.3 + 0.5,
				"life": 9 + (U.p_random() % 5), "size0": 7.0, "size1": 17.0,
				"c0": Color(1.0, 0.9, 0.62, 0.5), "c1": Color(1.0, 0.3, 0.06, 0.0),
				"frame": float(U.p_random() & 7), "frameRate": 0.6,
				"drag": 0.94, "gravity": 0.06,
			})
	trail.tic()
	# and the cold ones, which fly the same way and arrive differently:
	# no trail behind them and no heat under them
	var S := shards
	S.tic(func(i: int, nx: float, ny: float, nz: float) -> bool:
		var wall := lv.ray_hit_wall(S.px[i], S.py[i], S.pz[i], nx, ny, nz)
		if not wall.is_empty():
			_land_cold(wall.x, wall.y, wall.z)
			return true
		var sec := lv.span_at(nx, ny, S.pz[i])
		var floor := sec.floor if sec else 0.0
		if nz <= floor + 1.0:
			_land_cold(nx, ny, floor)
			return true
		return false)

## A piece has come down: a mark where it hit, a pool sometimes, and
## NOTHING THAT CATCHES (see LIGHT_FLOOR).
func _land(at: Vector3, kind: int, n: Vector3, vx: float, vy: float, frame := 0, size := 12.0) -> void:
	var D = _decals()
	# A PIECE OF VISCERA off a warhead lands WET: a big spatter thrown the
	# way it was flying, on whatever it hit, and a pool under it one time
	# in four — not every time, or sixty pieces is sixty pools and the
	# ring has eaten the room's walls by the time they are down.
	if kind == K_GORE or kind == K_BORE:
		var sp := maxf(1e-6, Vector2(vx, vy).length())
		if D != null:
			D.blood(at, n, Vector3(vx / sp, vy / sp, 0.0 if n == UP else -0.4), 26.0 + randf() * 30.0)
		if n == UP and (U.p_random() & 3) == 0:
			splat(at.x, at.y, at.z, 28.0 + randf() * 24.0)
		# AND THE PART ITSELF STAYS: on the floor where it fell, or slid down
		# the wall it hit to the floor at its foot
		if kind == K_BORE or randi() % REMAINS_GORE_EVERY == 0:
			var p := at
			if n != UP:
				p = at + Vector3(n.x, n.y, 0.0) * 5.0
				var s: Level.Sector = game.level.span_at(p.x, p.y, at.z)
				p.z = s.floor if s else at.z
			remain(p, frame, size)
		return
	# a piece that was never alight lands as blood, not as sparks
	if kind != K_SPURT and D != null:
		D.blood(at, n, Vector3(randf() - 0.5, randf() - 0.5, 0.0), 12.0 + randf() * 16.0)
	if n == UP and U.p_random() < GIB.splatChance:
		splat(at.x, at.y, at.z, 24.0 + randf() * 16.0)

## And a cold one, which is the same minus every single thing that was
## warm about it: ice does not bleed, it leaves the cold coming off it.
func _land_cold(x: float, y: float, z: float) -> void:
	var fx = _fx()
	if fx != null and (U.p_random() & 3) == 0:
		fx.frost_puff(x, y, z + 6.0, 12.0, 24)

## Once a frame.
func draw() -> void:
	chunks.draw()
	shards.draw()
	trail.draw()
	if _ash_dirty:
		_draw_ash()
	if _rem_dirty:
		_draw_remains()

# ------------------------------------------------------------------
# THE BORE'S FINISH, and what it leaves
# ------------------------------------------------------------------

## The cerebral bore is done drilling: THE HEAD GOES, absurdly. Everything
## a warhead does to a body (eviscerate) twice over, then the head's own
## parts flung up and out — brains, eyes, teeth — then a spray of blood
## like a burst main, pools round the feet, and the neck still pumping
## for three seconds after (fountains). Every piece that lands stays
## where it lands for a minute (remains).
func bore_explode(a) -> void:
	if a == null or a.get("vehicle") or a.frozen:
		return
	bore_finishes += 1
	var h := _stood(a)
	var head := Vector3(a.x, a.y, a.z + h * 0.86)
	# the body, as a warhead would leave it — from just under the chin, so
	# it all goes up
	eviscerate(a, head - Vector3(0, 0, 26.0), BORE_GORE.force)
	# THE HEAD'S OWN PARTS
	for k in BORE_GORE.parts:
		var ang := _r() * TAU
		var sp: float = BORE_GORE.speedMin + _r() * (BORE_GORE.speedMax - BORE_GORE.speedMin)
		var size: float = BORE_GORE.sizeMin + _r() * (BORE_GORE.sizeMax - BORE_GORE.sizeMin)
		var z: float = head.z - _r() * h * 0.5
		var vz: float = BORE_GORE.riseMin + _r() * (BORE_GORE.riseMax - BORE_GORE.riseMin)
		var life: float = 90 + (U.p_random() % 90)
		var c: Color = WET_GIB if (k & 1) == 0 else Color.WHITE
		var fr := float(HEAD_PARTS[U.p_random() % HEAD_PARTS.size()]) if k < BORE_GORE.parts / 2 else float(U.p_random() % GIBLETS)
		var i := chunks.put(a.x, a.y, z, cos(ang) * sp, sin(ang) * sp, vz, life, size, size, c, c, fr, 0.0, GORE.drag, GORE.gravity)
		if i >= 0:
			chunk_kind[i] = K_BORE
			chk_x[i] = a.x
			chk_y[i] = a.y
			chk_z[i] = z
			chunk_floor[i] = UNKNOWN
	var fx = _fx()
	if fx != null:
		fx.blood_spray(head.x, head.y, head.z, 0.0, 0.0, 1.0, BORE_GORE.spray, 2.4)
		for k in 10:
			fx.blood_puff(head.x + (_r() - 0.5) * 30.0, head.y + (_r() - 0.5) * 30.0, head.z + (k - 5) * 7.0)
	for k in BORE_GORE.pools:
		var ang := _r() * TAU
		var d := 20.0 + _r() * 70.0
		splat(a.x + cos(ang) * d, a.y + sin(ang) * d, a.z, 40.0 + _r() * 50.0)
	fountains.append({"x": a.x, "y": a.y, "z": a.z + h * 0.7, "tics": BORE_GORE.fountainTics})

## The necks still going: a jet up out of each, weakening as it goes.
func _fountains_tic() -> void:
	var fx = _fx()
	for i in range(fountains.size() - 1, -1, -1):
		var f: Dictionary = fountains[i]
		f.tics -= 1
		if f.tics <= 0 or fx == null:
			fountains.remove_at(i)
			continue
		var k: float = float(f.tics) / BORE_GORE.fountainTics
		# a pulse, like a heart still going
		if (tics % 6) < 3:
			fx.blood_spray(f.x, f.y, f.z, 0.0, 0.0, 1.0, int(2 + 6 * k), 0.9 + 1.4 * k)
		if tics % 9 == 0 and randf() < k:
			spurt({"x": f.x, "y": f.y, "z": f.z - 40.0, "height": 48.0}, 1)

## A part, left on the floor at `at`.
func remain(at: Vector3, frame: int, size: float) -> void:
	var s: Level.Sector = game.level.span_at(at.x, at.y, at.z)
	remains.append([at.x, at.y, at.z + 0.5, clampi(frame, 0, GIBLETS - 1), clampf(size, 7.0, 26.0), tics,
		randi() & 1, s.light if s else 0.7, s.sky if s else 0.0])
	while remains.size() > REMAINS_MAX:
		remains.pop_front()
	_rem_dirty = true

## The old ones go, and the going ones sink: every few tics.
func _remains_tic() -> void:
	if remains.is_empty():
		return
	while not remains.is_empty() and tics - int(remains[0][5]) >= REMAINS_TICS:
		remains.pop_front()
		_rem_dirty = true
	if tics % 4 == 0 and tics - int(remains[0][5]) >= REMAINS_TICS - REMAINS_FADE:
		_rem_dirty = true

func _make_remains_batch() -> void:
	var quad := ArrayMesh.new()
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-0.5, 0, 0), Vector3(0.5, 0, 0), Vector3(0.5, 1, 0), Vector3(-0.5, 1, 0)])
	arr[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)])
	arr[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	quad.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://godot/shaders/standee.gdshader")
	mat.set_shader_parameter("strip", U.col(load("res://assets/people/giblets.png")))
	mat.set_shader_parameter("cells", U.col(float(GIBLETS)))
	mat.set_shader_parameter("cell", U.col(Vector2(16, 16)))
	quad.surface_set_material(0, mat)
	_rem_mm = MultiMesh.new()
	_rem_mm.transform_format = MultiMesh.TRANSFORM_3D
	_rem_mm.use_custom_data = true
	_rem_mm.mesh = quad
	_rem_mm.instance_count = REMAINS_MAX
	_rem_mm.visible_instance_count = 0
	_rem_buf.resize(REMAINS_MAX * 16)
	var mi := MultiMeshInstance3D.new()
	mi.name = "Remains"
	mi.multimesh = _rem_mm
	mi.custom_aabb = AABB(Vector3(-1e6, -1e5, -1e6), Vector3(2e6, 2e5, 2e6))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

## All of them in one write: the scale is the part's size (a card is
## sixteen units, one to the pixel) and how far it has sunk.
func _draw_remains() -> void:
	_rem_dirty = false
	var n := remains.size()
	var b := _rem_buf
	for k in n:
		var r: Array = remains[k]
		var left: int = REMAINS_TICS - (tics - int(r[5]))
		var sc: float = float(r[4]) / 16.0 * clampf(float(left) / REMAINS_FADE, 0.0, 1.0)
		var p := U.v3(r[0], r[1], r[2])
		var o := k * 16
		b[o] = sc; b[o + 1] = 0.0; b[o + 2] = 0.0; b[o + 3] = p.x
		b[o + 4] = 0.0; b[o + 5] = sc; b[o + 6] = 0.0; b[o + 7] = p.y
		b[o + 8] = 0.0; b[o + 9] = 0.0; b[o + 10] = sc; b[o + 11] = p.z
		b[o + 12] = float(r[3]); b[o + 13] = r[7]; b[o + 14] = r[8]; b[o + 15] = float(r[6])
	_rem_mm.buffer = b
	_rem_mm.visible_instance_count = n

func live_count() -> int:
	return chunks.count + shards.count + trail.count

# ------------------------------------------------------------------
# THE ASH: a heap, not a stain (js/sprites.js, the ASH stand-ins)
# ------------------------------------------------------------------

func _make_ash_batch() -> void:
	var quad := ArrayMesh.new()
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-0.5, 0, 0), Vector3(0.5, 0, 0), Vector3(0.5, 1, 0), Vector3(-0.5, 1, 0)])
	arr[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)])
	arr[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	quad.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://godot/shaders/standee.gdshader")
	mat.set_shader_parameter("strip", U.col(ImageTexture.create_from_image(bake_ash_strip())))
	mat.set_shader_parameter("cells", U.col(float(ASHES)))
	mat.set_shader_parameter("cell", U.col(ASH_CELL))
	quad.surface_set_material(0, mat)
	_ash_mm = MultiMesh.new()
	_ash_mm.transform_format = MultiMesh.TRANSFORM_3D
	_ash_mm.use_custom_data = true
	_ash_mm.mesh = quad
	_ash_mm.instance_count = GIB.maxSplats
	_ash_mm.visible_instance_count = 0
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = _ash_mm
	mi.custom_aabb = AABB(Vector3(-1e6, -1e5, -1e6), Vector3(2e6, 2e5, 2e6))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

func _draw_ash() -> void:
	_ash_dirty = false
	var lv: Level = game.level
	for k in ash_piles.size():
		var p: Array = ash_piles[k]
		var s := lv.span_at(p[0], p[1], p[2])
		_ash_mm.set_instance_transform(k, Transform3D(Basis(), U.v3(p[0], p[1], p[2])))
		_ash_mm.set_instance_custom_data(k, Color(float(p[3]), s.light if s else 0.7, s.sky if s else 0.0, 0.0))
	_ash_mm.visible_instance_count = ash_piles.size()

## THREE LAYERS AND THE ORDER MATTERS: a wide scatter of pale grey (the
## ash that went sideways and settled, and what says "ash" rather than
## "hole"), then the heap itself, banked toward the middle — mid-grey,
## not the bottom of the ramp, which came out a black puddle — and then
## half a dozen coals, rust and yellow, which stop it reading as a
## puddle of dirty water. Squashed, because it lies on the floor and this
## is a billboard standing up on it. Three of them, side by side.
static func bake_ash_strip() -> Image:
	var W := int(ASH_CELL.x)
	var H := int(ASH_CELL.y)
	var img := Image.create(W * ASHES, H, false, Image.FORMAT_RGBA8)
	for v in ASHES:
		# js/util.js makeRng(631 + v); a lambda captures by value, so the
		# state lives in an array
		var st := [631 + v]
		var rng := func() -> float:
			st[0] = Effects._rng_next(st[0])
			return st[0] / 4294967296.0
		var cx := W / 2.0
		var cy := H - 4.0
		var wide := 10.0 + v * 2.0
		for i in 60:
			var a: float = rng.call() * TAU
			var d: float = sqrt(rng.call()) * (wide + 6.0)
			_disc(img, v * W, W, cx + cos(a) * d, cy + sin(a) * d * 0.26, 0.8 + rng.call() * 1.4, Effects.ramp("grey", 0.30 + rng.call() * 0.16))
		for i in 80:
			var a: float = rng.call() * TAU
			var d: float = pow(rng.call(), 1.8) * wide
			_disc(img, v * W, W, cx + cos(a) * d, cy + sin(a) * d * 0.30 - rng.call() * 2.0, 1.0 + rng.call() * 2.0, Effects.ramp("grey", 0.10 + rng.call() * 0.16))
		for i in 7:
			var a: float = rng.call() * TAU
			var d: float = pow(rng.call(), 1.5) * wide * 0.7
			var key := "yellow" if rng.call() < 0.35 else "rust"
			_disc(img, v * W, W, cx + cos(a) * d, cy + sin(a) * d * 0.30 - 1.0, 0.8 + rng.call() * 0.8, Effects.ramp(key, 0.36 + rng.call() * 0.3))
	return img

static func _disc(img: Image, ox: int, w: int, cx: float, cy: float, r: float, c: Color) -> void:
	var r2 := r * r
	var n := ceili(r)
	for y in range(-n, n + 1):
		for x in range(-n, n + 1):
			if x * x + y * y > r2:
				continue
			var px := floori(cx + x)
			var py := floori(cy + y)
			if px < 0 or px >= w or py < 0 or py >= img.get_height():
				continue
			img.set_pixel(ox + px, py, c)
