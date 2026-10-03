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
## A 3D VIEWPORT WHOSE PICTURE IS READ AS NUMBERS, the same under both
## renderers. Compatibility writes a fragment's colour out as it is;
## Mobile (at the user's request) encodes it to sRGB on the way out unless
## the viewport is HDR, so under Mobile it is made HDR and its picture is
## the raw colour, as it was. (And no shader of the game's marks a
## texture or a colour source_color: Compatibility ignores the hint, and
## Mobile would decode what it marks.)
## THE GLOBAL SHADER UNIFORMS, as last set: every one is set through
## gset, which keeps a copy here, because the Mobile renderer will not
## read one back outside the editor (RealDecals lights its marks off
## these).
static var G := {}
## METRES A GAME UNIT as the world is drawn (1/32 on the island: the game
## is scaled down to its metres — Game.start_map); the shaders' game_unit
static var unit_m := 1.0
static func set_unit(m: float) -> void:
	unit_m = m
	gset("game_unit", m)

static func gset(name: String, value) -> void:
	G[name] = value
	RenderingServer.global_shader_parameter_set(name, value)

## A COLOUR FOR A MATERIAL'S UNIFORM, the same under both renderers.
## Mobile takes a Color handed to a material as sRGB and decodes it to
## linear, hint or no hint; Compatibility (the look the game was tuned on)
## hands it over as it is. So under Mobile it is encoded first, and the
## decode lands on the value meant. Anything that is not a Color passes.
## (The global uniforms are not touched by either renderer.)
static var _rd := -1
static func col(v):
	if not (v is Color):
		return v
	if _rd < 0:
		_rd = 1 if RenderingServer.get_rendering_device() != null else 0
	return (v as Color).linear_to_srgb() if _rd == 1 else v

static func raw_out(v: SubViewport) -> void:
	if RenderingServer.get_rendering_device() != null:
		v.use_hdr_2d = true

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

