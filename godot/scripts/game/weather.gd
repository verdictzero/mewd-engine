## MEWD — the clock, the weather and the wind (js/weather.js).
##
## One state, read by everybody, so the hour, the distance the air lets
## you see, the direction the smoke drifts and the rain are one fact.
## TIME OF DAY IS ONE NUMBER, the hour, and everything is a table lookup
## on it. THE GAME IS A NIGHT: it starts at two in the morning and runs
## at a rate that brings the sun up in about nine minutes of play — you
## have until dawn. WEATHER IS A ROW multiplied over the hour's row.
## The fire's own haze comes on by degrees over whatever is running.
## The numbers go into the shaders' globals (world_light.gdshaderinc).
class_name Weather
extends RefCounted

const KEYFRAMES := [
	{"hour": 22.0, "zenith": "#0a1030", "horizon": "#182240", "ground": "#07080c", "sunAlt": -34, "sunCol": "#000000", "glow": "#000000", "glowAmt": 0.0,
		"moonAlt": 48, "moonAz": -1.2, "town": 0.55, "stars": 1.0, "milky": 0.9, "skyLight": 0.10, "minLight": 0.22, "falloff": 3400},
	{"hour": 2.0, "zenith": "#080c26", "horizon": "#141c38", "ground": "#050608", "sunAlt": -52, "sunCol": "#000000", "glow": "#000000", "glowAmt": 0.0,
		"moonAlt": 36, "moonAz": -2.0, "town": 0.5, "stars": 1.0, "milky": 1.0, "skyLight": 0.08, "minLight": 0.22, "falloff": 3400},
	{"hour": 4.5, "zenith": "#0c1430", "horizon": "#2a3450", "ground": "#0a0c12", "sunAlt": -9, "sunCol": "#8090b0", "glow": "#4a5570", "glowAmt": 0.55,
		"moonAlt": 18, "moonAz": -2.7, "town": 0.3, "stars": 0.5, "milky": 0.3, "skyLight": 0.22, "minLight": 0.26, "falloff": 4200},
	{"hour": 5.17, "zenith": "#182446", "horizon": "#6a5878", "ground": "#1a161e", "sunAlt": -4, "sunCol": "#e0a080", "glow": "#d08060", "glowAmt": 0.9,
		"moonAlt": 10, "moonAz": -2.9, "town": 0.1, "stars": 0.06, "milky": 0.0, "skyLight": 0.45, "minLight": 0.32, "falloff": 5200},
	{"hour": 5.67, "zenith": "#4a6aa8", "horizon": "#d8b890", "ground": "#3a3630", "sunAlt": 0, "sunCol": "#fff0c0", "glow": "#ffd090", "glowAmt": 1.0,
		"moonAlt": 4, "moonAz": -3.05, "town": 0.0, "stars": 0.0, "milky": 0.0, "skyLight": 0.75, "minLight": 0.40, "falloff": 7000},
	{"hour": 6.5, "zenith": "#5a86c8", "horizon": "#c8d4e0", "ground": "#46484a", "sunAlt": 9, "sunCol": "#fff8e0", "glow": "#ffe8b0", "glowAmt": 0.6,
		"moonAlt": -5, "moonAz": -3.1, "town": 0.0, "stars": 0.0, "milky": 0.0, "skyLight": 0.95, "minLight": 0.48, "falloff": 9000},
	{"hour": 8.0, "zenith": "#5080c8", "horizon": "#bcd0e4", "ground": "#4c4e50", "sunAlt": 24, "sunCol": "#fffcf0", "glow": "#fff0d0", "glowAmt": 0.35,
		"moonAlt": -20, "moonAz": -3.1, "town": 0.0, "stars": 0.0, "milky": 0.0, "skyLight": 1.0, "minLight": 0.52, "falloff": 9000},
]
## the sun's azimuth (0 east, a quarter turn north) and where the town's glow is
const SUN_AZ := 0.35
const WEATHERS := {
	"clear": {"name": "CLEAR", "airNear": 1200, "airFar": 14000, "skyMul": 1.00, "stars": 1.0, "cover": 0.18, "cloudDark": 1.0, "flat": 0.0, "rain": 0.0, "wind": [0.28, 0.05], "haze": "#000000"},
	"overcast": {"name": "OVERCAST", "airNear": 800, "airFar": 9000, "skyMul": 0.80, "stars": 0.0, "cover": 0.92, "cloudDark": 0.8, "flat": 0.0, "rain": 0.0, "wind": [0.40, 0.10], "haze": "#0c0c10"},
	"rain": {"name": "RAIN", "airNear": 500, "airFar": 5200, "skyMul": 0.70, "stars": 0.0, "cover": 1.0, "cloudDark": 0.6, "flat": 0.0, "rain": 1.0, "wind": [0.90, 0.20], "haze": "#101014"},
	"mist": {"name": "MIST", "airNear": 200, "airFar": 2600, "skyMul": 0.85, "stars": 0.0, "cover": 0.0, "cloudDark": 1.0, "flat": 1.0, "rain": 0.0, "wind": [0.05, 0.00], "haze": "#2c2c32"},
}
const ORDER := ["clear", "overcast", "rain", "mist"]
const HOURS_PER_MINUTE := 0.4
const SMOKE_HOT := 320.0
const SMOKE_WOOD := 200.0
const SMOKE_RISE := 40.0
const SMOKE_FALL := 150.0
const SMOKE_AIR := [220.0, 2400.0]

var hour := 2.0
var kind := "clear"
var rate := HOURS_PER_MINUTE
var running := true
var smoke := 0.0
var frame := {}
## a map's own sky colours over the hour's (Weather.skin): the grid's green
var sky_skin := {}
## the sky material the frame is pushed into, when the map has no skybox
var sky_mat: ShaderMaterial = null
var cloud_time := 0.0

static func night_hour(h: float) -> float:
	var x := fposmod(h, 24.0)
	if x < 12.0:
		x += 24.0
	return clampf(x, 22.0, 32.0)

static func sample_hour(h0: float) -> Dictionary:
	var h := night_hour(h0)
	var rows := KEYFRAMES.map(func(k): var r: Dictionary = k.duplicate(); r.at = night_hour(k.hour); return r)
	rows.sort_custom(func(a, b): return a.at < b.at)
	var a: Dictionary = rows[0]
	var b: Dictionary = rows[rows.size() - 1]
	for i in rows.size() - 1:
		if h >= rows[i].at and h <= rows[i + 1].at:
			a = rows[i]
			b = rows[i + 1]
			break
	var t: float = 0.0 if a == b or b.at == a.at else clampf((h - a.at) / (b.at - a.at), 0.0, 1.0)
	var out := {"hour": h - 24.0 if h > 24.0 else h, "sunAz": SUN_AZ}
	for k in ["zenith", "horizon", "ground", "sunCol", "glow"]:
		out[k] = Color(a[k]).lerp(Color(b[k]), t)
	for k in ["sunAlt", "skyLight", "minLight", "falloff", "glowAmt", "moonAlt", "moonAz", "town", "stars", "milky"]:
		out[k] = lerpf(a[k], b[k], t)
	var dl := clampf((out.sunAlt + 12.0) / 15.0, 0.0, 1.0)
	out.daylight = dl * dl * (3.0 - 2.0 * dl)
	return out

static func sample_frame(h: float, k := "clear", smoke_k := 0.0) -> Dictionary:
	var f := sample_hour(h)
	var w: Dictionary = WEATHERS.get(k, WEATHERS.clear)
	var haze := Color(w.haze)
	for c in ["zenith", "horizon", "ground"]:
		var v: Color = f[c]
		f[c] = Color(minf(1, v.r + haze.r), minf(1, v.g + haze.g), minf(1, v.b + haze.b))
	f.airNear = float(w.airNear)
	f.airFar = float(w.airFar)
	f.skyLight *= w.skyMul
	f.rain = w.rain
	f.wind = Vector2(w.wind[0], w.wind[1])
	f.stars *= w.stars
	f.milky *= w.stars
	f.cover = w.cover
	f.cloudDark = w.cloudDark
	f.flat = w.flat
	var s := clampf(smoke_k, 0.0, 1.0)
	if s > 0.0:
		# the fire's own sky, a wildfire afternoon's: a paper-bag zenith
		f.zenith = f.zenith.lerp(Color(0.30, 0.15, 0.06), s * 0.9)
		f.horizon = f.horizon.lerp(Color(0.68, 0.34, 0.12), s * 0.92)
		f.ground = f.ground.lerp(Color(0.26, 0.12, 0.05), s * 0.9)
		f.sunCol = f.sunCol.lerp(Color(1.0, 0.36, 0.10), s)
		f.glowAmt *= 1.0 + s * 0.8
		f.cover = maxf(f.cover, s * 0.96)
		f.cloudDark = lerpf(f.cloudDark, 0.5, s)
		f.stars *= 1.0 - s
		f.milky *= 1.0 - s
		f.skyLight *= 1.0 - 0.55 * s
		f.airNear = lerpf(f.airNear, minf(f.airNear, SMOKE_AIR[0]), s)
		f.airFar = lerpf(f.airFar, minf(f.airFar, SMOKE_AIR[1]), s)
		f.wind = f.wind * (1.0 + s)
	return f

func _init(opts := {}) -> void:
	hour = opts.get("hour", 2.0)
	kind = opts.get("kind", "clear")
	frame = sample_frame(hour, kind, 0.0)

func tic() -> void:
	if running:
		hour += rate / 60.0 / U.TICRATE
		if night_hour(hour) >= 32.0:
			hour = 8.0

## The clock's picture into the shaders. (The fire's haze, `smoke`, is
## always clear now: the fire that spread is gone.)
func apply(dt: float) -> Dictionary:
	smoke = 0.0
	cloud_time += dt
	frame = skin(sample_frame(hour, kind, smoke))
	var f := frame
	if sky_mat != null:
		_push_sky(f)
	RenderingServer.global_shader_parameter_set("air_near", f.airNear)
	RenderingServer.global_shader_parameter_set("air_far", f.airFar)
	RenderingServer.global_shader_parameter_set("sky_light", f.skyLight)
	RenderingServer.global_shader_parameter_set("light_falloff", f.falloff)
	RenderingServer.global_shader_parameter_set("min_light", f.minLight)
	RenderingServer.global_shader_parameter_set("global_light", 1.0)
	return f

func skin(f: Dictionary) -> Dictionary:
	var k := sky_skin
	if k.is_empty():
		return f
	for c in ["zenith", "horizon", "ground"]:
		if k.has(c):
			f[c] = Color(k[c])
	if k.has("mid"):
		f.mid = Color(k.mid)
		f.midAmt = k.get("midAmt", 1.0)
		f.midPow = k.get("midPow", 1.0)
	if k.get("bare", false):
		f.cover = 0.0
		f.stars = 0.0
		f.milky = 0.0
		f.glowAmt = 0.0
		f.town = 0.0
		f.moonAlt = -90.0
	return f

static func _dir(az: float, alt_deg: float) -> Vector3:
	var a := deg_to_rad(alt_deg)
	return Vector3(cos(az) * cos(a), sin(a), -sin(az) * cos(a))

func _push_sky(f: Dictionary) -> void:
	var m := sky_mat
	for k in ["zenith", "horizon", "ground", "glow"]:
		m.set_shader_parameter(k, f[k])
	m.set_shader_parameter("sun_col", f.sunCol)
	m.set_shader_parameter("mid", f.get("mid", f.horizon))
	m.set_shader_parameter("mid_amt", f.get("midAmt", 0.0) if f.has("mid") else 0.0)
	m.set_shader_parameter("mid_pow", f.get("midPow", 1.0))
	m.set_shader_parameter("sun_dir", _dir(f.sunAz, f.sunAlt))
	m.set_shader_parameter("glow_amt", f.glowAmt)
	m.set_shader_parameter("sun_up", clampf((f.sunAlt + 0.6) / 1.2, 0.0, 1.0))
	m.set_shader_parameter("moon_dir", _dir(f.moonAz, f.moonAlt))
	var moon: float = clampf((f.moonAlt + 2.0) / 4.0, 0.0, 1.0) * (1.0 - f.cover * 0.5) * (1.0 - f.flat) if f.moonAlt > -2.0 else 0.0
	m.set_shader_parameter("moon_amt", moon)
	m.set_shader_parameter("town", f.town)
	m.set_shader_parameter("stars", f.stars)
	m.set_shader_parameter("milky", f.milky)
	m.set_shader_parameter("daylight", f.daylight)
	m.set_shader_parameter("cover", f.cover)
	m.set_shader_parameter("cloud_dark", f.cloudDark)
	m.set_shader_parameter("flatness", f.flat)
	m.set_shader_parameter("cloud_time", cloud_time)
	m.set_shader_parameter("wind", Vector2(f.wind.x, -f.wind.y))
	# and the air fades to the horizon, as the web build's does to its
	# texel — which the bake wrote snapped to the palette and then linear
	# (js/skyart.js, THE PAINT), so it is that colour and not the byte
	if not _air_memo.has(f.horizon):
		_air_memo.clear()
		_air_memo[f.horizon] = Weather.pal_snap(f.horizon).srgb_to_linear()
	RenderingServer.global_shader_parameter_set("air_color", _air_memo[f.horizon])

var _air_memo := {}
static var _lut: Image = null

## The nearest of the palette's colours, as the lo-fi pass snaps (the
## 32x32x32 atlas, godot/data/palette_lut.png: blue picks the slice, red
## is x within it, green is y).
static func pal_snap(c: Color) -> Color:
	if _lut == null:
		var t: Texture2D = load("res://godot/data/palette_lut.png")
		_lut = t.get_image()
		if _lut.is_compressed():
			_lut.decompress()
	var r := int(floor(clampf(c.r, 0.0, 1.0) * 31.0 + 0.5))
	var g := int(floor(clampf(c.g, 0.0, 1.0) * 31.0 + 0.5))
	var b := int(floor(clampf(c.b, 0.0, 1.0) * 31.0 + 0.5))
	return _lut.get_pixel(b * 32 + r, g)

func wind() -> Vector2:
	return frame.get("wind", Vector2(0.28, 0.05))

## the clock as the pause menu shows it
func label() -> String:
	var h := fposmod(hour, 24.0)
	return "%02d:%02d" % [int(h), int((h - int(h)) * 60.0)]
