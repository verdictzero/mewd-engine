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
	{"hour": 22.0, "zenith": "#0a1030", "horizon": "#182240", "ground": "#07080c", "sunAlt": -34, "skyLight": 0.10, "minLight": 0.22, "falloff": 3400},
	{"hour": 2.0, "zenith": "#080c26", "horizon": "#141c38", "ground": "#050608", "sunAlt": -52, "skyLight": 0.08, "minLight": 0.22, "falloff": 3400},
	{"hour": 4.5, "zenith": "#0c1430", "horizon": "#2a3450", "ground": "#0a0c12", "sunAlt": -9, "skyLight": 0.22, "minLight": 0.26, "falloff": 4200},
	{"hour": 5.17, "zenith": "#182446", "horizon": "#6a5878", "ground": "#1a161e", "sunAlt": -4, "skyLight": 0.45, "minLight": 0.32, "falloff": 5200},
	{"hour": 5.67, "zenith": "#4a6aa8", "horizon": "#d8b890", "ground": "#3a3630", "sunAlt": 0, "skyLight": 0.75, "minLight": 0.40, "falloff": 7000},
	{"hour": 6.5, "zenith": "#5a86c8", "horizon": "#c8d4e0", "ground": "#46484a", "sunAlt": 9, "skyLight": 0.95, "minLight": 0.48, "falloff": 9000},
	{"hour": 8.0, "zenith": "#5080c8", "horizon": "#bcd0e4", "ground": "#4c4e50", "sunAlt": 24, "skyLight": 1.0, "minLight": 0.52, "falloff": 9000},
]
const WEATHERS := {
	"clear": {"name": "CLEAR", "airNear": 1200, "airFar": 14000, "skyMul": 1.00, "rain": 0.0, "wind": [0.28, 0.05], "haze": "#000000"},
	"overcast": {"name": "OVERCAST", "airNear": 800, "airFar": 9000, "skyMul": 0.80, "rain": 0.0, "wind": [0.40, 0.10], "haze": "#0c0c10"},
	"rain": {"name": "RAIN", "airNear": 500, "airFar": 5200, "skyMul": 0.70, "rain": 1.0, "wind": [0.90, 0.20], "haze": "#101014"},
	"mist": {"name": "MIST", "airNear": 200, "airFar": 2600, "skyMul": 0.85, "rain": 0.0, "wind": [0.05, 0.00], "haze": "#2c2c32"},
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
var fire_haze := true
var frame := {}

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
	var out := {}
	for k in ["zenith", "horizon", "ground"]:
		out[k] = Color(a[k]).lerp(Color(b[k]), t)
	for k in ["sunAlt", "skyLight", "minLight", "falloff"]:
		out[k] = lerpf(a[k], b[k], t)
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
	var s := clampf(smoke_k, 0.0, 1.0)
	if s > 0.0:
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

## The clock's picture into the shaders. `burn` and `wood` are how much of
## the place is alight (0..1); `hot` how many cells are burning.
func apply(dt: float, burn := 0.0, wood := 0.0, hot := 0.0) -> Dictionary:
	var target := minf(1.0, hot / SMOKE_HOT + (burn + wood) * 0.7) if fire_haze else 0.0
	if not fire_haze:
		smoke = 0.0
	else:
		var tau := SMOKE_RISE if target > smoke else SMOKE_FALL
		smoke += (target - smoke) * minf(1.0, dt / tau)
		if target == 0.0 and smoke < 0.003:
			smoke = 0.0
	frame = sample_frame(hour, kind, smoke)
	var f := frame
	RenderingServer.global_shader_parameter_set("air_near", f.airNear)
	RenderingServer.global_shader_parameter_set("air_far", f.airFar)
	RenderingServer.global_shader_parameter_set("sky_light", f.skyLight)
	RenderingServer.global_shader_parameter_set("light_falloff", f.falloff)
	RenderingServer.global_shader_parameter_set("min_light", f.minLight + burn * 0.30)
	RenderingServer.global_shader_parameter_set("global_light", 1.0 + burn * 0.22)
	return f

func wind() -> Vector2:
	return frame.get("wind", Vector2(0.28, 0.05))

## the clock as the pause menu shows it
func label() -> String:
	var h := fposmod(hour, 24.0)
	return "%02d:%02d" % [int(h), int((h - int(h)) * 60.0)]
