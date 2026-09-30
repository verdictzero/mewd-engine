## MEWD — embers and smoke, and a person on fire (js/effects.js).
##
## A fire that only glows is a picture of a fire. What sells it is what
## comes OFF it: sparks lifting on the heat and going out, and smoke
## standing up over it and drifting away. Both are cheap if they are
## budgeted, and this is the budget: a few hundred embers and a couple
## of hundred puffs at most, alive at once, in two draw calls.
##
## WHERE THEY COME FROM: off the people and the cars that are alight
## (the fire that spread across the floor is gone, at the user's
## request, and with it the sampling of its cells).
##
## EMBERS are cutout quads a couple of units across, bright gold going
## to dark coal, lifted by the heat and then falling, and they die when
## they land. SMOKE is a soft blob, alpha-blended, that grows and fades
## as it climbs; it is lit by the room like anything else. And two pools
## beside those: the FIRE PEOPLE CARRY (bodyFire, the muzzle, fireballs)
## and the BLOOD IN THE AIR when somebody is blown apart (bloodSpray).
##
## THE PICTURES are baked here, as in js/effects.js bakeEffectAtlases:
## a spark, eight puffs of smoke that are one puff turning over, and
## eight fireballs — which are also what the gun's stream is made of
## (js/main.js streamAtlas); see Effects.atlases().
class_name Effects
extends Node3D

## How many frames of drifting smoke there are. One loop, not a set of
## variants — see bake_atlases.
const SMOKE_PUFFS := 8
const FIREBALLS := 8

## TONGUES, NOT A BONFIRE. The first cut threw two a tic at up to
## thirty-four units, which on a fifty-six-unit person is a column of
## fire with somebody lost inside it, and the point of a burning shopper
## is that you can see WHO is burning. One a tic, smaller, and gone
## sooner — about a dozen alive on one person — leaves the drawing
## showing through.
const BODY_FIRE := {
	"near": 1400.0,      # past this a burning person is a glow, not a fire
	"most": 14,          # how many of them may throw flame in one tic
	"perTic": 1,         # licks each, a tic
	"lifeMin": 8, "lifeMax": 17,
	"sizeMin": 10.0, "sizeMax": 25.0,
	"rise": 0.75,        # how fast a lick climbs
	"lift": 6.0,         # and how far toward the eye it spawns, so it is in
	                     # front of the person rather than fighting their quad
	# AND THE SPARKS ARE RATIONED TOO, against the same pools the store's
	# own fire throws from: every fourth tic, phased off the actor's id so
	# they are not in step
	"emberEvery": 4,     # tics between sparks off one of them
	"smokeEvery": 10,    # and between puffs
}

## js/palette.js EMBER_RAMP: dark coal to hot gold
const EMBER_RAMP := [Color8(0x18, 0x10, 0x08), Color8(0x30, 0x20, 0x00), Color8(0x50, 0x30, 0x00), Color8(0x70, 0x40, 0x00),
	Color8(0x98, 0x58, 0x00), Color8(0xc0, 0x78, 0x20), Color8(0xe8, 0x98, 0x58), Color8(0xf8, 0xd0, 0xa0)]

var game
var embers: Particles
var smoke: Particles
var body_flames: Particles
var gore: Particles
## which of the gore pool's slots are DROPS (1) rather than mist (0):
## a drop stops at the floor, the mist at nothing
var gore_kind := PackedByteArray()
## the per-tic budget and the light the burning bodies throw, both reset
## by the first caller in a tic rather than by the frame
var _fire_tic := -1
var _fire_left := 0
var glow := {"sx": 0.0, "sy": 0.0, "sw": 0.0, "n": 0}

func _init(g, body_atlas: Dictionary = {}) -> void:
	game = g
	var at := atlases()
	embers = Particles.new({"max": 640, "map": at.spark, "frames": 1, "blend": "mix", "fullbright": true,
		"near_shrink": 160.0, "order": 12})
	# Raised from 240 when the fire grew a body of smoke of its own: these
	# are the DRIFTING half of it, what comes off the top of the plume and
	# goes where the wind takes it.
	smoke = Particles.new({"max": 360, "map": at.smoke, "frames": SMOKE_PUFFS, "blend": "mix", "fullbright": false,
		"near_shrink": 90.0, "order": 14})
	smoke.mat.set_shader_parameter("light", 0.55)
	# THE FIRE PEOPLE CARRY. Its own pool and not the store's, because the
	# store's flames are PARKED on hot cells; these are spawned at the
	# body and left where they were spawned, and the difference is the
	# trail. Additive, so a person well alight adds up toward white.
	var bmap = body_atlas.get("texture", at.fireball)
	body_flames = Particles.new({"max": 460, "map": bmap, "frames": int(body_atlas.get("frames", FIREBALLS)), "blend": "add",
		"fullbright": true, "near_shrink": 40.0, "order": 13})
	# AND THE BLOOD IN THE AIR WHEN SOMEBODY IS BLOWN APART, its own pool
	# for the reason the body fire is: a warhead through a crowd wants
	# several hundred of these at once, for a second, and in the smoke's
	# pool that is a second in which every fire stops smoking. Same puffs,
	# drawn dark red and shaded by the room, and they FALL.
	gore = Particles.new({"max": 700, "map": at.smoke, "frames": SMOKE_PUFFS, "blend": "mix", "fullbright": false,
		"near_shrink": 60.0, "order": 14})
	gore.mat.set_shader_parameter("light", 0.7)
	gore_kind.resize(gore.max)
	for p in [embers, smoke, body_flames, gore]:
		add_child(p)

## the wind, as the fire feels it (js/weather.js climate.wind)
func _wind() -> Vector2:
	var f = game.get("fire")
	return f.wind if f != null else Vector2(0.28, 0.05)

static func _r() -> float:
	return U.p_random() / 255.0

# ------------------------------------------------------------------
# A PERSON ON FIRE: the flame on them, the light they throw
# ------------------------------------------------------------------

func _new_tic() -> void:
	if _fire_tic == game.tics:
		return
	_fire_tic = game.tics
	_fire_left = BODY_FIRE.most
	glow.sx = 0.0; glow.sy = 0.0; glow.sw = 0.0; glow.n = 0

## Something that is not a body pulling the one fire light toward
## itself: a vehicle charring, a rifle going off. `w` is how much of the
## light it is worth against a burning person's one.
func glow_at(x: float, y: float, w := 1.0) -> void:
	_new_tic()
	glow.sx += x * w; glow.sy += y * w; glow.sw += w; glow.n += 1

## One burning body, one tic of fire off it (from Actor.burn_tic).
## `scale` is for a body being EATEN rather than running: on fire too,
## but the flame has to stay off the drawing.
func body_fire(a, scale := 1.0) -> int:
	var p = game.player
	if p == null or a.removed:
		return 0
	_new_tic()
	var d2 := U.dist2(a.x, a.y, p.x, p.y)
	# THE LIGHT IS NOT BUDGETED AND NOT RANGED THE SAME WAY: a torch three
	# aisles off is not worth a particle and is very much worth its glow
	glow.sx += a.x * scale; glow.sy += a.y * scale; glow.sw += scale; glow.n += 1
	if d2 > BODY_FIRE.near * BODY_FIRE.near or _fire_left <= 0:
		return 0
	_fire_left -= 1
	var B := BODY_FIRE
	var h: float = a.height if a.height > 8.0 else 56.0
	var inv := 1.0 / maxf(1.0, sqrt(d2))
	var lx: float = (p.x - a.x) * inv * B.lift
	var ly: float = (p.y - a.y) * inv * B.lift
	var w := _wind()
	var n := maxi(1, roundi(B.perTic * scale))
	for k in n:
		# UP THE BODY AND BIGGEST AT THE MIDDLE: bright at the chest with
		# tongues off the shoulders
		var up := _r()
		var size: float = (B.sizeMin + (B.sizeMax - B.sizeMin) * (1.0 - absf(up - 0.45) * 1.6)) * scale
		body_flames.spawn({
			"x": a.x + lx + (_r() - 0.5) * 11.0, "y": a.y + ly + (_r() - 0.5) * 11.0, "z": a.z + 4.0 + up * h * 0.9,
			"vx": (_r() - 0.5) * 0.5 + w.x * 0.5, "vy": (_r() - 0.5) * 0.5 + w.y * 0.5, "vz": B.rise + _r() * 0.7,
			"life": B.lifeMin + (U.p_random() % (B.lifeMax - B.lifeMin)),
			"size0": maxf(6.0, size), "size1": maxf(3.0, size * 0.35),
			"c0": Color(1, 1, 1, 0.95), "c1": Color(1, 0.72, 0.34, 0.0),
			"frame": float(U.p_random() % body_flames.frames), "frameRate": 0.55,
			"drag": 0.93, "gravity": -0.02,
		})
	# and the sparks and the smoke off them, the parts of the trail that
	# outlast the flame and go where the wind does
	if (game.tics + a.id) % B.emberEvery == 0:
		ember(a.x, a.y, a.z + h * 0.5, 1, 0.9 * scale)
	if (game.tics + a.id) % B.smokeEvery == 0:
		puff(a.x, a.y, a.z + h * 1.05, 20.0 * scale, 120)
	return n

## The one fire light, pulled toward everybody who is alight — the
## protocol the light on the walls could read (nothing does yet).
func glow_into(acc: Dictionary) -> void:
	if glow.sw <= 0.0:
		return
	acc.sx += glow.sx; acc.sy += glow.sy; acc.sw += glow.sw; acc.n += glow.n

## A RIFLE GOING OFF: the flash is on the drawing, so what is needed here
## is its light on the aisle for a frame and a spit of hot gas out of the
## muzzle — two licks, gone in a quarter of a second.
func muzzle(a) -> void:
	glow_at(a.x, a.y, 2.5)
	var c := cos(a.angle)
	var s := sin(a.angle)
	var h: float = (a.height if a.height > 8.0 else 56.0) * 0.66
	for k in 2:
		var out := 16.0 + k * 9.0
		body_flames.spawn({
			"x": a.x + c * out, "y": a.y + s * out, "z": a.z + h,
			"vx": c * 1.4, "vy": s * 1.4, "vz": 0.2,
			"life": 4 + k * 3, "size0": 14.0 - k * 4.0, "size1": 4.0,
			"c0": Color(1, 0.95, 0.7, 0.9), "c1": Color(1, 0.55, 0.15, 0.0),
			"frame": float(U.p_random() % body_flames.frames), "frameRate": 0.8,
			"drag": 0.8, "gravity": 0.0,
		})

# ------------------------------------------------------------------
# Spawning
# ------------------------------------------------------------------

func ember(x: float, y: float, z: float, n := 1, heat := 1.0) -> void:
	var w := _wind()
	for k in n:
		var a := _r() * TAU
		var sp := 0.3 + _r() * 1.4
		embers.spawn({
			"x": x + (_r() - 0.5) * 18.0, "y": y + (_r() - 0.5) * 18.0, "z": z,
			"vx": cos(a) * sp + w.x, "vy": sin(a) * sp + w.y, "vz": 1.3 + _r() * 2.2 * heat,
			"life": 40 + (U.p_random() % 60),
			"size0": 1.5 + _r() * 1.2, "size1": 0.8,
			"c0": EMBER_RAMP[7], "c1": EMBER_RAMP[2 + (U.p_random() & 1)],
			"drag": 0.985, "gravity": -0.055,
		})

func puff(x: float, y: float, z: float, size := 28.0, life := 150) -> void:
	var warm := 0.55 + _r() * 0.3
	var w := _wind()
	smoke.spawn({
		"x": x + (_r() - 0.5) * 24.0, "y": y + (_r() - 0.5) * 24.0, "z": z,
		"vx": (_r() - 0.5) * 0.5 + w.x * 1.6, "vy": (_r() - 0.5) * 0.5 + w.y * 1.6, "vz": 0.9 + _r() * 0.7,
		"life": life + (U.p_random() % 60),
		"size0": size, "size1": size * 4.2,
		"c0": Color(0.34 * warm, 0.30 * warm, 0.28 * warm, 0.55), "c1": Color(0.16, 0.16, 0.18, 0.0),
		# AND IT WALKS THE LOOP: a smooth churn through the eight frames
		# twice over while it rises, rather than three pops
		"frame": float(U.p_random() % SMOKE_PUFFS), "frameRate": 0.09,
		"drag": 0.992, "gravity": 0.004,
	})

## Blood in the air, out of the top of a drilled head: the smoke's own
## frames, small, dark red, and gone quickly — a mist over the fountain
## of pieces Giblets throws, so the spurt has a body.
func blood_puff(x: float, y: float, z: float) -> void:
	smoke.spawn({
		"x": x + (_r() - 0.5) * 6.0, "y": y + (_r() - 0.5) * 6.0, "z": z,
		"vx": (_r() - 0.5) * 0.6, "vy": (_r() - 0.5) * 0.6, "vz": 0.9 + _r() * 0.8,
		"life": 14 + (U.p_random() % 10), "size0": 7.0, "size1": 16.0,
		"c0": Color(0.62, 0.05, 0.04, 0.75), "c1": Color(0.30, 0.02, 0.02, 0.0),
		"frame": float(U.p_random() % SMOKE_PUFFS), "frameRate": 0.2,
		"drag": 0.95, "gravity": -0.01,
	})

## A SPRAY OF BLOOD out of (x, y, z), thrown along d — or every way at
## once if that is zero — `n` of it, at `force`. Two things in one call,
## because a body coming apart is two things: a MIST that hangs and
## spreads, dark red going brown, and DROPS, small and fast and heavy,
## that arc out and come down, which is what makes it read as liquid
## rather than as smoke. The drops stop at the floor and leave nothing:
## the decals are what is left, and the caller lays those.
func blood_spray(x: float, y: float, z: float, dx := 0.0, dy := 0.0, dz := 0.0, n := 12, force := 1.0) -> void:
	var dl := sqrt(dx * dx + dy * dy + dz * dz)
	for k in n:
		var th := _r() * TAU
		var ph := _r() * 2.0 - 1.0
		var cs := sqrt(1.0 - ph * ph)
		# a direction: round the throw if there is one, anywhere if not
		var ux := cos(th) * cs
		var uy := sin(th) * cs
		var uz := absf(ph) * 0.8 + 0.2
		if dl > 0.0:
			ux = ux * 0.55 + dx / dl
			uy = uy * 0.55 + dy / dl
			uz = uz * 0.55 + dz / dl + 0.3
		var sp := force * (1.5 + _r() * 6.5)
		var drop := (k & 1) == 0
		var i := gore.spawn({
			"x": x + (_r() - 0.5) * 10.0, "y": y + (_r() - 0.5) * 10.0, "z": z,
			"vx": ux * sp, "vy": uy * sp, "vz": uz * sp * (1.1 if drop else 0.4),
			"life": (26 + (U.p_random() % 22)) if drop else (30 + (U.p_random() % 30)),
			"size0": float(4 + (U.p_random() & 3)) if drop else float(12 + (U.p_random() % 12)),
			"size1": 3.0 if drop else float(34 + (U.p_random() % 20)),
			"c0": Color(0.55, 0.02, 0.02, 1.0) if drop else Color(0.62, 0.04, 0.035, 0.82),
			"c1": Color(0.35, 0.01, 0.01, 0.9) if drop else Color(0.28, 0.03, 0.02, 0.0),
			"frame": float(U.p_random() % SMOKE_PUFFS), "frameRate": 0.0 if drop else 0.15,
			"drag": 0.985 if drop else 0.93, "gravity": -0.42 if drop else -0.03,
		})
		if i >= 0:
			gore_kind[i] = 1 if drop else 0

## Where a flame landed: a spit of sparks and a little smoke.
func splash(x: float, y: float, z: float) -> void:
	ember(x, y, z + 6.0, 2, 0.8)
	if (U.p_random() & 3) == 0:
		puff(x, y, z + 10.0, 18.0, 90)

## THE SAME PUFFS, COLD: near-white and blue, BRIEF where smoke hangs
## about, and it falls instead of rising — cold gas is heavier than the
## air it is in, and a jet of it pools along the floor.
func frost_puff(x: float, y: float, z: float, size := 22.0, life := 40) -> void:
	smoke.spawn({
		"x": x + (_r() - 0.5) * 16.0, "y": y + (_r() - 0.5) * 16.0, "z": z,
		"vx": (_r() - 0.5) * 0.8, "vy": (_r() - 0.5) * 0.8, "vz": -0.15 - _r() * 0.35,
		"life": life + (U.p_random() % 30), "size0": size, "size1": size * 2.6,
		"c0": Color(0.82, 0.94, 1.05, 0.5), "c1": Color(0.40, 0.56, 0.72, 0.0),
		"frame": float(U.p_random() % SMOKE_PUFFS), "frameRate": 0.22,
		"drag": 0.94, "gravity": -0.006,
	})

## Where the extinguisher's stream landed.
func chill_splash(x: float, y: float, z: float) -> void:
	frost_puff(x, y, z + 8.0, 18.0, 30)

## JET WASH: grit thrown OUTWARD along a surface, fast and low, gone
## inside a second. `k` is how hard the engine blows on this spot; `n`
## the surface's normal says which way "along" is.
func wash(x: float, y: float, z: float, k := 1.0, n := Vector3(0, 0, 1)) -> void:
	var a := _r() * TAU
	var sp := (1.8 + _r() * 2.8) * (0.5 + 0.5 * k)
	var u := Vector3(1, 0, 0) if absf(n.z) > 0.5 else Vector3(-n.y, n.x, 0)
	var v := Vector3(0, 1, 0) if absf(n.z) > 0.5 else Vector3(0, 0, 1)
	var dir := (u * cos(a) + v * sin(a)) * sp
	var pale := 0.55 + _r() * 0.25
	smoke.spawn({
		"x": x + (_r() - 0.5) * 30.0, "y": y + (_r() - 0.5) * 30.0, "z": z + 3.0,
		"vx": dir.x + n.x * 0.4, "vy": dir.y + n.y * 0.4, "vz": dir.z * 0.6 + n.z * 0.5,
		"life": 16 + (U.p_random() % 14), "size0": 14.0 + 10.0 * k, "size1": 46.0 + 30.0 * k,
		"c0": Color(0.50 * pale, 0.47 * pale, 0.44 * pale, 0.34 * (0.4 + 0.6 * k)), "c1": Color(0.30, 0.29, 0.28, 0.0),
		"frame": float(U.p_random() % SMOKE_PUFFS), "frameRate": 0.25,
		"drag": 0.91, "gravity": -0.03,
	})

## A FIREBALL: the body-fire pool's additive frames at many times the
## size a shopper carries, rising slowly and dying to orange. One call
## is one ball; a bang is a dozen of them.
func fireball(x: float, y: float, z: float, size := 90.0, life := 22) -> void:
	body_flames.spawn({
		"x": x + (_r() - 0.5) * size * 0.6, "y": y + (_r() - 0.5) * size * 0.6, "z": z + (_r() - 0.5) * size * 0.5,
		"vx": (_r() - 0.5) * 2.2, "vy": (_r() - 0.5) * 2.2, "vz": 0.8 + _r() * 1.6,
		"life": life + (U.p_random() % 12), "size0": size * 0.55, "size1": size * 1.35,
		"c0": Color(1, 1, 1, 1), "c1": Color(1, 0.45, 0.12, 0.0),
		"frame": float(U.p_random() % body_flames.frames), "frameRate": 0.45,
		"drag": 0.94, "gravity": -0.01,
	})

# ------------------------------------------------------------------
# One tic
# ------------------------------------------------------------------

func tic() -> void:
	var lv: Level = game.level
	embers.tic(func(_i: int, nx: float, ny: float, nz: float) -> bool:
		# embers go out on the floor (of the storey they were in)
		var s := lv.span_at(nx, ny, embers.pz[_i])
		return nz <= (s.floor if s else 0.0) + 1.0)
	smoke.tic()
	# the licks stop at a wall for the same reason the stream's do
	body_flames.tic(func(_i: int, nx: float, ny: float, nz: float) -> bool:
		var s := lv.span_at(nx, ny, body_flames.pz[_i])
		return s == null or nz <= s.floor - 2.0 or nz >= s.ceil)
	if gore.count > 0:
		gore.tic(func(i: int, nx: float, ny: float, nz: float) -> bool:
			if gore_kind[i] != 1:
				return false
			var s := lv.span_at(nx, ny, gore.pz[i])
			return s == null or nz <= s.floor + 1.0)

## Once a frame.
func draw() -> void:
	embers.draw()
	smoke.draw()
	body_flames.draw()
	gore.draw()

func live_count() -> int:
	return embers.count + smoke.count + gore.count

# ------------------------------------------------------------------
# The pictures: a spark, eight puffs of smoke, eight fireballs,
# generated like all the other art (js/effects.js bakeEffectAtlases)
# ------------------------------------------------------------------

static var _atlases := {}

## {spark, smoke, fireball}: ImageTextures, frames side by side. Baked
## once and shared — the gun's stream wants the fireballs:
##   Particles.new({..., "map": Effects.atlases().fireball, "frames": Effects.FIREBALLS})
static func atlases() -> Dictionary:
	if _atlases.is_empty():
		_atlases = bake_atlases()
	return _atlases

static func bake_atlases() -> Dictionary:
	var spark := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	spark.fill(ramp("bone", 1.0))
	# EIGHT PUFFS THAT ARE ONE PUFF, which is the fix for smoke that
	# popped: one fbm field whose lattice wraps after PW rows, sampled with
	# a vertical offset of PW/N per frame. Frame N is frame 0 again, every
	# step between them the same small scroll, so a puff turns over over
	# its life rather than flickering.
	const PW := 32
	var pn := fbm(PW, PW, 4, 3, 70)
	var puffs := Image.create(PW * SMOKE_PUFFS, PW, false, Image.FORMAT_RGBA8)
	for f in SMOKE_PUFFS:
		var off := roundi(f * PW / float(SMOKE_PUFFS))
		for y in PW:
			for x in PW:
				var sy := (y + off) % PW
				var d := Vector2((x - 15.5) / 15.5, (y - 15.5) / 15.5).length()
				var edge := maxf(0.0, 1.0 - d)
				var a := clampf(edge * 1.8 * (0.45 + pn[sy * PW + x] * 0.8) - 0.15, 0.0, 1.0)
				if a <= 0.05:
					continue
				puffs.set_pixel(f * PW + x, y, Color8(235, 232, 230, roundi(a * 255)))
	# The stream's particle: a ball of fire, white at the heart through
	# the ember colours to a soft dark-red rim, eight of them so a stream
	# is not one blob repeated. Drawn additively, so where they overlap
	# they add up to white — which is what makes a dense arc read as one
	# flame rather than beads on a string.
	var balls := Image.create(32 * FIREBALLS, 32, false, Image.FORMAT_RGBA8)
	for f in FIREBALLS:
		var n := fbm(32, 32, 4, 3, 300 + f * 17)
		for y in 32:
			for x in 32:
				var d := Vector2((x - 15.5) / 15.5, (y - 15.5) / 15.5).length()
				var v := clampf((1.0 - d) * (0.6 + n[y * 32 + x] * 0.8), 0.0, 1.0)
				if v < 0.06:
					continue
				var c := ramp("fire", minf(1.0, v * 1.15))
				c.a8 = roundi(minf(1.0, v / 0.35) * 255)
				balls.set_pixel(f * 32 + x, y, c)
	return {
		"spark": ImageTexture.create_from_image(spark),
		"smoke": ImageTexture.create_from_image(puffs),
		"fireball": ImageTexture.create_from_image(balls),
	}

## js/palette.js's ramps this file and Giblets draw with (the stock box):
## stops, smoothstep between them, `gamma` bending where the entries sit.
const RAMPS := {
	"grey": {"n": 24, "gamma": 1.30, "stops": [[0.0, [6, 7, 11]], [0.5, [92, 94, 102]], [1.0, [248, 248, 252]]]},
	"bone": {"n": 16, "gamma": 1.25, "stops": [[0.0, [22, 20, 17]], [0.5, [130, 124, 108]], [1.0, [244, 238, 216]]]},
	"yellow": {"n": 16, "gamma": 1.15, "stops": [[0.0, [20, 16, 4]], [0.5, [168, 144, 24]], [1.0, [252, 248, 140]]]},
	"rust": {"n": 16, "gamma": 1.20, "stops": [[0.0, [16, 9, 6]], [0.5, [118, 62, 30]], [1.0, [224, 150, 92]]]},
	"fire": {"n": 44, "gamma": 1.0, "stops": [[0.00, [0, 0, 0]], [0.10, [34, 0, 0]], [0.24, [96, 6, 0]], [0.40, [168, 26, 0]],
		[0.56, [226, 74, 6]], [0.72, [248, 142, 14]], [0.87, [252, 216, 62]], [1.00, [255, 255, 226]]]},
}
static var _ramp_cache := {}

static func ramp(key: String, t: float) -> Color:
	if not _ramp_cache.has(key):
		var spec: Dictionary = RAMPS[key]
		var out := []
		var n: int = spec.n
		for i in n:
			var u := pow(float(i) / (n - 1), 1.0 if spec.gamma == 1.0 else 1.0 / spec.gamma)
			var stops: Array = spec.stops
			var k := 0
			while k < stops.size() - 2 and u > stops[k + 1][0]:
				k += 1
			var f := clampf((u - stops[k][0]) / maxf(1e-6, stops[k + 1][0] - stops[k][0]), 0.0, 1.0)
			var s := f * f * (3.0 - 2.0 * f)
			var c0: Array = stops[k][1]
			var c1: Array = stops[k + 1][1]
			out.append(Color8(roundi(c0[0] + (c1[0] - c0[0]) * s), roundi(c0[1] + (c1[1] - c0[1]) * s), roundi(c0[2] + (c1[2] - c0[2]) * s)))
		_ramp_cache[key] = out
	var r: Array = _ramp_cache[key]
	return r[clampi(roundi(t * (r.size() - 1)), 0, r.size() - 1)]

## js/util.js makeRng: xorshift32, as the JS runs it
static func _rng_next(s: int) -> int:
	s = (s ^ (s << 13)) & 0xFFFFFFFF
	s = s ^ (s >> 17)
	s = (s ^ (s << 5)) & 0xFFFFFFFF
	return s

## js/pixel.js valueNoise: a lattice of `cells` that wraps, smoothstepped
static func value_noise(w: int, h: int, cells: int, seed: int) -> PackedFloat32Array:
	var s := seed & 0xFFFFFFFF
	if s == 0:
		s = 0x9e3779b9
	var g := PackedFloat32Array()
	g.resize(cells * cells)
	for i in g.size():
		s = _rng_next(s)
		g[i] = s / 4294967296.0
	var out := PackedFloat32Array()
	out.resize(w * h)
	var sx := float(cells) / w
	var sy := float(cells) / h
	for y in h:
		var fy := y * sy
		var iy := floori(fy)
		var ty := fy - iy
		var wy := ty * ty * (3.0 - 2.0 * ty)
		var y0 := posmod(iy, cells)
		var y1 := (y0 + 1) % cells
		for x in w:
			var fx := x * sx
			var ix := floori(fx)
			var tx := fx - ix
			var wx := tx * tx * (3.0 - 2.0 * tx)
			var x0 := posmod(ix, cells)
			var x1 := (x0 + 1) % cells
			var a := g[y0 * cells + x0]
			var b := g[y0 * cells + x1]
			var c := g[y1 * cells + x0]
			var d := g[y1 * cells + x1]
			var top := a + (b - a) * wx
			out[y * w + x] = top + ((c + (d - c) * wx) - top) * wy
	return out

## js/pixel.js fbm: octaves of value noise, each twice as fine and half
## as strong
static func fbm(w: int, h: int, base_cells: int, octaves: int, seed: int, gain := 0.5) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(w * h)
	var amp := 1.0
	var total := 0.0
	var cells := base_cells
	for o in octaves:
		var n := value_noise(w, h, cells, seed + o * 7919)
		for i in out.size():
			out[i] += n[i] * amp
		total += amp
		amp *= gain
		cells *= 2
		if cells > w:
			break
	for i in out.size():
		out[i] /= total
	return out
