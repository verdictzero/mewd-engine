## MEWD — the numbers everything shares (js/util.js).
##
## MAP SPACE is Doom's: x east, y north, z up, in units (a person is 56
## tall, 32 units to the metre as the eye reads it). Godot's space is
## the renderer's: Y up, -Z forward — so a map point (x, y, z) is drawn
## at Vector3(x, z, -y), everywhere, through U.v3().
class_name U

const TICRATE := 35
const SEC := 1.0 / TICRATE

const PLAYER_RADIUS := 16.0
const PLAYER_HEIGHT := 56.0
const PLAYER_EYE := 49.0
const MAX_STEP := 24.0
const TEXEL := 64.0

## the map point (x, y) at height z, where Godot draws it
static func v3(x: float, y: float, z: float) -> Vector3:
	return Vector3(x, z, -y)

static func angle_norm(a: float) -> float:
	return wrapf(a, -PI, PI)

static func dist2(ax: float, ay: float, bx: float, by: float) -> float:
	var dx := ax - bx
	var dy := ay - by
	return dx * dx + dy * dy

## The same linear congruential generator the JS maps use
## ((s * 1664525 + 1013904223) >>> 0), so one seed is one map in both.
class Rng:
	var s: int
	func _init(seed: int) -> void:
		s = seed & 0xFFFFFFFF
		if s == 0:
			s = 1
	func next() -> float:
		s = (s * 1664525 + 1013904223) & 0xFFFFFFFF
		return float(s) / 4294967296.0
	func ri(a: int, b: int) -> int:
		return a + int(next() * (b - a + 1))
	func pick(a: Array):
		return a[int(next() * a.size())]

## Where segment a->b crosses c->d, as the fraction along a->b, or -1.
static func seg_intersect(ax: float, ay: float, bx: float, by: float, cx: float, cy: float, dx: float, dy: float) -> float:
	var rx := bx - ax
	var ry := by - ay
	var sx := dx - cx
	var sy := dy - cy
	var den := rx * sy - ry * sx
	if absf(den) < 1e-12:
		return -1.0
	var t := ((cx - ax) * sy - (cy - ay) * sx) / den
	var u := ((cx - ax) * ry - (cy - ay) * rx) / den
	if t < 0.0 or t > 1.0 or u < 0.0 or u > 1.0:
		return -1.0
	return t

static func closest_on_seg(ax: float, ay: float, bx: float, by: float, px: float, py: float) -> Vector2:
	var dx := bx - ax
	var dy := by - ay
	var d2 := dx * dx + dy * dy
	var t := 0.0 if d2 <= 0.0 else clampf(((px - ax) * dx + (py - ay) * dy) / d2, 0.0, 1.0)
	return Vector2(ax + dx * t, ay + dy * t)

static func point_in_poly(poly: PackedVector2Array, x: float, y: float) -> bool:
	var inside := false
	var n := poly.size()
	var j := n - 1
	for i in n:
		var a := poly[i]
		var b := poly[j]
		if (a.y > y) != (b.y > y) and x < (b.x - a.x) * (y - a.y) / (b.y - a.y) + a.x:
			inside = not inside
		j = i
	return inside

## GAMEPLAY RANDOMNESS, 0..255, the way Doom's P_Random works — an
## xorshift32 here, as in js/util.js. Nobody needs it reproducible
## except the tests, which reseed it.
static var _pr := 0x1f2e3d4c

static func p_seed(v: int = 0x1f2e3d4c) -> void:
	_pr = v if v != 0 else 0x1f2e3d4c

static func p_random() -> int:
	var s := _pr & 0xFFFFFFFF
	s ^= (s << 13) & 0xFFFFFFFF
	s ^= s >> 17
	s ^= (s << 5) & 0xFFFFFFFF
	_pr = s
	return s & 255

## A FONT FOR THE UI: the system's (the first of `names` it has), with
## the bundled DejaVu behind it for any glyph it lacks — or, in a web
## page, which has no system fonts to lend, the bundled DejaVu itself
## (assets/fonts/dejavu/, the Bitstream Vera licence beside it).
static func ui_font(names: PackedStringArray, mono := true, weight := 400) -> Font:
	var bold := weight >= 600
	var own: Font = load("res://assets/fonts/dejavu/DejaVuSans%s%s.ttf" % ["Mono" if mono else "", "-Bold" if bold else ""])
	if OS.has_feature("web"):
		return own
	var f := SystemFont.new()
	f.font_names = names
	f.font_weight = weight
	f.fallbacks = [own]
	return f

