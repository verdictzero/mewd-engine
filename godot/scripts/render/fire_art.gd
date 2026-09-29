## MEWD — the fire, drawn (js/fireart.js).
##
## Every flame in the game comes out of this file. One generator, three
## sizes (ember, fire, blaze), so all of it is visibly the same fire.
##
## THE ROUND BOTTOM IS THE FIRST THING DRAWN. The flame is a chain of
## circles: a BALL at the foot, then a column of smaller and smaller
## circles up to a point. The bottom of the shape is the bottom of that
## ball, which is round because a circle is — a mask cannot round a
## bottom, only drawing one can.
##
## FOUR MORE THINGS MAKE IT A FIRE RATHER THAN A LAVA LAMP: THE LICK (the
## chain's axis sways, loosest at the tip), THE BITE (a noise field
## scrolling upward eats the edge, hard at the top), THE STREAKS (a finer
## field that only decides how hot each pixel inside is) and THE HEAT
## (white at the foot to dull red at the tip, in EIGHT BANDS — the
## contour bands a painted flame has, not an airbrushed blob).
##
## AND IT LOOPS EXACTLY: the lattice wraps after a whole number of rows
## and the scroll over `count` frames is exactly that distance, so the
## last frame hands over to the first with nothing moving.
class_name FireArt

## Shared with the animation: fewer frames means bigger jumps between
## them, and twenty is where it stops looking stepped.
const FIRE_FRAMES := 20
const BLAZE_FRAMES := 20
const EMBER_FRAMES := 14

## Where the lowest point of the flame sits in its cell, up from the
## bottom row as a fraction of the height.
const FLAME_FOOT := 0.05

## The shape, in fractions of the cell
const FLAME := {
	"wide": 0.58,   # widest half-width, as a fraction of the half cell
	"tall": 0.21,   # and as a fraction of the flame's own height, whichever is less
	"slim": 1.15,   # how fast it closes going up
	"lick": 0.50,   # how far the tip wanders, as a fraction of the half cell
	"bite": 1.05,   # how far the noise moves the edge, against the widest half-width
	"grain": 0.17,  # noise cell, as a fraction of the cell width
	"rise": 0.075,  # how far the pattern climbs per frame, as a fraction of the height
	"warp": 1.40,   # above 1, the pattern speeds up as it rises
	"discs": 26,    # how many circles the body is made of
	"foot": FLAME_FOOT,
	"head": 0.10,   # headroom above the tip, for the licks that break off it
}

## Three octaves of value noise land in about 0.5 +/- 0.15; this opens
## it out to roughly +/-1 so `bite` means what it says.
const NGAIN := 2.6
const BANDS := 8

## THE FIRE RAMP (js/palette.js, the stock box): seven stops, 44 entries,
## bunched toward the bottom because most of a flame is the dull end.
const RAMP_N := 44
const RAMP_STOPS := [
	[0.00, [0, 0, 0]], [0.10, [34, 0, 0]], [0.24, [96, 6, 0]], [0.40, [168, 26, 0]],
	[0.56, [226, 74, 6]], [0.72, [248, 142, 14]], [0.87, [252, 216, 62]], [1.00, [255, 255, 226]],
]

static var _ramp: Array = []

## js/palette.js rampColors: smoothstep between stops, gamma 1
static func ramp(t: float) -> Array:
	if _ramp.is_empty():
		for i in RAMP_N:
			var u := float(i) / (RAMP_N - 1)
			var k := 0
			while k < RAMP_STOPS.size() - 2 and u > RAMP_STOPS[k + 1][0]:
				k += 1
			var p0: float = RAMP_STOPS[k][0]
			var p1: float = RAMP_STOPS[k + 1][0]
			var c0: Array = RAMP_STOPS[k][1]
			var c1: Array = RAMP_STOPS[k + 1][1]
			var f := clampf((u - p0) / maxf(1e-6, p1 - p0), 0.0, 1.0)
			var s := f * f * (3.0 - 2.0 * f)
			_ramp.append([clampi(roundi(c0[0] + (c1[0] - c0[0]) * s), 0, 255),
				clampi(roundi(c0[1] + (c1[1] - c0[1]) * s), 0, 255),
				clampi(roundi(c0[2] + (c1[2] - c0[2]) * s), 0, 255)])
	return _ramp[clampi(roundi(t * (RAMP_N - 1)), 0, RAMP_N - 1)]

const M32 := 0xFFFFFFFF

## Math.imul's low 32 bits, then the ordinary integer mix
static func _ihash(x: int, y: int, s: int) -> float:
	var n := ((x * 374761393) & M32) ^ ((y * 668265263) & M32) ^ ((s * 2246822519) & M32)
	n = ((n ^ (n >> 13)) * 1274126177) & M32
	return float((n ^ (n >> 16)) & M32) / 4294967296.0

## Value noise on a lattice whose rows wrap after `period` of them.
static func _loop_noise(x: float, y: float, cell: float, period: int, s: int) -> float:
	var gx := floori(x / cell)
	var gy := floori(y / cell)
	var fx := x / cell - gx
	var fy := y / cell - gy
	var u := fx * fx * (3.0 - 2.0 * fx)
	var v := fy * fy * (3.0 - 2.0 * fy)
	var ya := posmod(gy, period)
	var yb := (ya + 1) % period
	var a := _ihash(gx, ya, s)
	var b := _ihash(gx + 1, ya, s)
	var c := _ihash(gx, yb, s)
	var d := _ihash(gx + 1, yb, s)
	var top := a + (b - a) * u
	return top + ((c + (d - c) * u) - top) * v

## Three octaves, each halving the cell and doubling the period, so they
## all repeat over the same distance.
static func _loop_fbm(x: float, y: float, cell: float, period: int, s: int) -> float:
	return 0.54 * _loop_noise(x, y, cell, period, s) \
		+ 0.31 * _loop_noise(x, y, cell * 0.5, period * 2, s + 91) \
		+ 0.15 * _loop_noise(x, y, cell * 0.25, period * 4, s + 197)

## One fire, as a horizontal strip of `count` cells of w by h. `taper`
## is how fat the flame is; anything in FLAME can be overridden beside it.
static func fire_frames(w: int, h: int, count: int, seed := 7, opts := {}) -> Image:
	var F := FLAME.duplicate()
	F.merge(opts, true)
	var fat := 0.72 + 0.5 * float(opts.get("taper", 0.55))
	var f_wide: float = F.wide
	var f_tall: float = F.tall
	var f_slim: float = F.slim
	var f_lick: float = F.lick
	var f_bite: float = F.bite
	var f_warp: float = F.warp
	var f_foot: float = F.foot
	var f_head: float = F.head
	var f_grain: float = F.grain
	var f_rise: float = F.rise
	var cx := (w - 1) * 0.5
	var half_w := (w - 1) * 0.5
	var y_foot := (h - 1) * (1.0 - f_foot)
	var H := y_foot - (h - 1) * f_head
	# A FLAME IS TALLER THAN IT IS WIDE, whatever cell it is handed
	var rmax: float = minf(half_w * f_wide, H * f_tall) * fat
	# THE WIDEST CIRCLE IS THE LOWEST ONE — the invariant that keeps the
	# bottom round for any cell and any setting
	var r0 := rmax
	var discs: int = F.discs
	var grain := maxf(2.5, w * f_grain)
	var period := maxi(2, roundi((h * f_rise * count) / grain))
	var span := period * grain
	var pad := ceili(rmax * f_bite * 0.5) + 2
	var field := PackedFloat32Array()
	field.resize(w * h)
	var img := Image.create(w * count, h, false, Image.FORMAT_RGBA8)
	for f in count:
		var ph := TAU * f / count
		field.fill(-1e9)
		for j in discs:
			var s := float(j) / (discs - 1)
			var r := maxf(0.4, rmax * pow(1.0 - s, f_slim))
			# the sway, pinned at the foot: only the top of a fire whips
			var lean: float = half_w * f_lick * pow(s, 1.6) * (0.62 * sin(ph + s * 3.1 + seed) + 0.38 * sin(2.0 * ph + s * 5.9 + 2.1))
			var ax := cx + lean
			var ay := y_foot - (r0 + s * (H - r0))
			for y in range(maxi(0, floori(ay - r - pad)), mini(h - 1, ceili(ay + r + pad)) + 1):
				var dy := y - ay
				for x in range(maxi(0, floori(ax - r - pad)), mini(w - 1, ceili(ax + r + pad)) + 1):
					var dx := x - ax
					var d := r - sqrt(dx * dx + dy * dy)
					var i := y * w + x
					if d > field[i]:
						field[i] = d
		var scroll := (float(f) / count) * span
		for y in h:
			var py := y_foot - y
			var s := clampf(py / H, 0.0, 1.0)
			# a warped height, so the pattern accelerates on the way up
			var ny: float = H * pow(s, f_warp) - scroll
			for x in w:
				var d := field[y * w + x]
				if d < -rmax:
					continue
				var n := _loop_fbm(x - cx, ny, grain, period, seed)
				# the streaks: finer, stretched tall, climbing twice as fast
				var ns := _loop_fbm((x - cx) * 2.2, ny * 0.55 - scroll * 2.0, grain, period, seed + 313)
				# the bite: nothing at the ball, enough at the top to sever a lick
				var dn: float = d + f_bite * rmax * (0.15 + s * s) * (n - 0.5) * NGAIN
				var a := dn * 0.95 + 0.5
				if a <= 0.03:
					continue
				# how hot: mostly height, darker at the edge
				var heat := (0.22 + 0.78 * pow(1.0 - s, 2.4)) * (0.52 + 0.48 * clampf(dn / 2.4, 0.0, 1.0)) * (0.78 + 0.44 * ns)
				# the fuel: a little extra heat right in the ball, kept noisy
				var bx := x - cx
				var by := py - r0 * 0.9
				var ball := clampf(1.0 - sqrt(bx * bx + by * by) / (r0 * 1.1), 0.0, 1.0)
				heat += 0.20 * ball * ball
				var band := roundf(clampf(minf(0.97, heat * (0.84 + 0.30 * n)), 0.0, 1.0) * BANDS) / BANDS
				var c := ramp(band)
				img.set_pixel(f * w + x, y, Color8(c[0], c[1], c[2], roundi(minf(1.0, a) * 255.0)))
	return img
