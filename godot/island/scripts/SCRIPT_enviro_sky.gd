class_name EnviroSky
extends Node3D

# THE SKY, THE CLOCK AND THE WEATHER OF A REAL PLACE, after Enviro 3 (at the
# user's request: "make a cloud sky etc system reminiscent of the enviro 3 unity
# plugin"). One node in the island's scene, standing in for golf's sky cycle
# (SCRIPT_sky_cycle_controller.gd): it owns
#
#   THE CLOCK: an hour, a day of the year and a year, held still or run at
#     `day_minutes` real minutes a day.
#   THE SUN AND THE MOON, where they really are for the place's latitude and
#     longitude at that hour (Paul Schlyter's low-precision formulae: the sun to
#     a hundredth of a degree, the moon to about one), so a region's sunrise
#     comes up over its real ridges and the moon's phase is the real one.
#   THE WEATHER: presets (EnviroWeather, godot/island/sky/enviro/weather/) from
#     CLEAR through FAIR, PARTLY CLOUDY, CLOUDY and OVERCAST to FOGGY, RAIN,
#     STORM and SNOW, the sky always on its way from where it was to the one
#     asked for, over `transition_seconds`. The pause menu's WEATHER chooses
#     (clear the island's own, overcast, rain, mist as foggy); an island's
#     Islands entry ("sky") or --sky-weather= picks the island's own.
#   THE SKY ITSELF: SHADER_sky_enviro.gdshader, every number of which is set
#     here — the air's scattering, the clouds raymarched and lit, the stars,
#     the moon, lightning.
#   THE ISLAND'S LIGHT: the same scattering, run here on the CPU a few times a
#     second, gives the sunlight reaching the ground, the sky's light, the
#     bounce and the horizon's colour, and those become the tod_* globals every
#     island surface is lit by (SHADERINC_island_light), the fog's tint
#     (tod_haze_tint) and density (tod_fog_density, tod_fog_near), the plants'
#     tint (tod_art_tint) and the crowd's light (`world_light`, which
#     Game._island_light asks for).
#   WHAT FALLS: rain and snow round the eye, and lightning in a storm — a flash
#     over the whole sky and the bolt in it.

const WEATHER_DIR := "res://godot/island/sky/enviro/weather"
## The pause menu's WEATHER, as presets ("clear" is the island's own).
const FROM_MENU := {"overcast": "overcast", "rain": "rain", "mist": "foggy"}

@export var sky_material: ShaderMaterial
@export var world_environment: NodePath = ^"../WorldEnvironment"
@export var island_world_path: NodePath = ^"../IslandWorld"

@export_group("Place and time")
## Degrees north and east. An EarthField island's own replace these.
@export var latitude := 46.5
@export var longitude := 7.7
## Hours ahead of UTC. NAN: the longitude's own (round(lon / 15)).
@export var utc_offset := NAN
@export var year := 2026
@export_range(1, 366) var day_of_year := 196
@export_range(0.0, 24.0) var hour := 10.5
## Real minutes the sky takes over a whole day; 0 holds the clock.
@export var day_minutes := 0.0
## Metres over sea level of the island's y = 0 (an EarthField's datum), and of
## its highest ground (where the clouds' base is measured from).
@export var ground_altitude := 0.0
@export var ground_top := 500.0

@export_group("Weather")
@export var weather := "fair"
@export var transition_seconds := 30.0
## Follow the pause menu's WEATHER.
@export var follow_menu := true

@export_group("Island")
## The island materials' own fog colour, which tod_haze_tint multiplies.
@export var fog_base := Color(0.62, 0.72, 0.84)
@export var cloud_steps := 40
@export var light_steps := 5

var _presets := {}
var _now := {}
var _target := {}
var _target_id := ""
var _wind_off := Vector2.ZERO
var _cirrus_off := Vector2.ZERO
var _sun := Vector3.UP
var _moon := Vector3.DOWN
var _cpu_t := 1.0
var _light := {}
var _flash := 0.0
var _bolt := 0.0
var _next_strike := 8.0
var _game: Node = null
var _rain: GPUParticles3D = null
var _snow: GPUParticles3D = null
var _forced_weather := ""
# the light on things that are not lit (the plants, the rain): tod_art_tint
var _art := Color.WHITE


func _ready() -> void:
	for f in DirAccess.get_files_at(WEATHER_DIR):
		var path := WEATHER_DIR.path_join(f.trim_suffix(".remap"))
		if not path.ends_with(".tres"):
			continue
		var w := load(path) as EnviroWeather
		if w != null:
			_presets[w.id] = w
	_take_place()
	_take_options()
	_now = _values(weather)
	_target = _now.duplicate()
	_target_id = weather
	_game = _find_game()
	_make_falls()
	var we := get_node_or_null(world_environment) as WorldEnvironment
	if we != null and sky_material != null and we.environment != null and we.environment.sky != null:
		we.environment.sky.sky_material = sky_material
	if sky_material != null:
		# the GL compatibility renderer has no quarter-resolution sky pass
		var compat := RenderingServer.get_current_rendering_method() == "gl_compatibility"
		sky_material.set_shader_parameter("clouds_in_main", compat)
		sky_material.set_shader_parameter("steps", cloud_steps if not compat else maxi(cloud_steps * 3 / 4, 16))
		sky_material.set_shader_parameter("light_steps", light_steps)
	_update(0.0, true)


func _exit_tree() -> void:
	# the fog's numbers are globals: leave them as every other island expects
	RenderingServer.global_shader_parameter_set("tod_fog_density", 1.0)
	RenderingServer.global_shader_parameter_set("tod_fog_near", 1.0)


## An EarthField island's latitude, longitude and heights; else the exports.
func _take_place() -> void:
	var iw := get_node_or_null(island_world_path)
	var f: Variant = iw.get("field") if iw != null else null
	if f is EarthField:
		var r: EarthField.Region = (f as EarthField).data()
		if r.ok:
			latitude = float(r.json.get("lat", latitude))
			longitude = float(r.json.get("lon", longitude))
			ground_altitude = r.datum
			ground_top = float(r.json.get("height", {}).get("max", ground_top))
	if is_nan(utc_offset):
		utc_offset = roundf(longitude / 15.0)


## --sky-hour=H, --sky-day=D, --sky-weather=ID, --sky-minutes=M; and the
## island's own "sky" in its Islands entry.
func _take_options() -> void:
	var g := _find_game()
	if g != null:
		var spec: Variant = g.get("island_spec")
		if spec is Dictionary and (spec as Dictionary).has("sky"):
			var s: Dictionary = spec.sky
			hour = float(s.get("hour", hour))
			day_of_year = int(s.get("day", day_of_year))
			weather = String(s.get("weather", weather))
			day_minutes = float(s.get("day_minutes", day_minutes))
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--sky-hour="):
			hour = float(a.substr(11))
		elif a.begins_with("--sky-day="):
			day_of_year = int(a.substr(10))
		elif a.begins_with("--sky-weather="):
			weather = a.substr(14)
			_forced_weather = weather
		elif a.begins_with("--sky-minutes="):
			day_minutes = float(a.substr(14))


func _find_game() -> Node:
	var n := get_parent()
	while n != null:
		if "weather" in n and "island_spec" in n:
			return n
		n = n.get_parent()
	return null


func _values(id: String) -> Dictionary:
	var w: EnviroWeather = _presets.get(id, _presets.get("fair"))
	if w == null:
		return EnviroWeather.new().values()
	return w.values()


## Change the weather; the sky gets there over `transition_seconds` (0: at once).
func set_weather(id: String, instantly := false) -> void:
	if not _presets.has(id):
		push_warning("EnviroSky: no weather '%s' (%s)" % [id, ", ".join(_presets.keys())])
		return
	weather = id
	_target_id = id
	_target = _values(id)
	if instantly:
		_now = _target.duplicate()


## Every weather there is.
func weathers() -> Array:
	var k := _presets.keys()
	k.sort()
	return k


func _process(dt: float) -> void:
	_update(dt, false)


func _update(dt: float, force: bool) -> void:
	if day_minutes > 0.0:
		hour += dt * 24.0 / (day_minutes * 60.0)
		if hour >= 24.0:
			hour -= 24.0
			day_of_year = day_of_year % 365 + 1
	# the pause menu's choice, when it has made one
	var want := weather
	if follow_menu and _forced_weather == "" and _game != null:
		var gw: Variant = _game.get("weather")
		if gw != null and "kind" in gw:
			want = FROM_MENU.get(String(gw.kind), weather)
	if want != _target_id:
		_target_id = want
		_target = _values(want)
	# toward it
	var k := 1.0 if transition_seconds <= 0.0 else clampf(dt / transition_seconds, 0.0, 1.0)
	for key in _target:
		var a: Variant = _now.get(key, _target[key])
		var b: Variant = _target[key]
		if a is Color:
			_now[key] = (a as Color).lerp(b, k)
		else:
			_now[key] = lerpf(float(a), float(b), k)
	_place_bodies()
	# the wind carries the clouds (faster aloft)
	var wf := deg_to_rad(float(_now.wind_from))
	var blow := -Vector2(sin(wf), -cos(wf)) * float(_now.wind)
	_wind_off += blow * dt * 4.0
	_cirrus_off += blow * dt * 7.0
	_storm(dt)
	_cpu_t += dt
	if force or _cpu_t > 0.2:
		_cpu_t = 0.0
		_light = _island_light()
	_push_sky()
	_push_globals()
	_push_falls()


# ------------------------------------------------------------------ astronomy

func _rev(x: float) -> float:
	return fposmod(x, 360.0)


func _sind(x: float) -> float:
	return sin(deg_to_rad(x))


func _cosd(x: float) -> float:
	return cos(deg_to_rad(x))


## Days since 2000 Jan 0.0 UT (Schlyter's d) at the clock.
func _day_number() -> float:
	var ut := hour - utc_offset
	var y := year
	var jan1 := Time.get_unix_time_from_datetime_dict({"year": y, "month": 1, "day": 1, "hour": 0, "minute": 0, "second": 0})
	return (jan1 - 946598400.0) / 86400.0 + float(day_of_year - 1) + ut / 24.0


## A body's direction from right ascension and declination (degrees), in the
## island's frame: x east, y up, z south.
func _sky_dir(ra: float, dec: float, lst: float) -> Vector3:
	var ha := lst * 15.0 - ra
	var x := _cosd(ha) * _cosd(dec)
	var y := _sind(ha) * _cosd(dec)
	var z := _sind(dec)
	var xh := x * _sind(latitude) - z * _cosd(latitude)
	var zh := x * _cosd(latitude) + z * _sind(latitude)
	var az := rad_to_deg(atan2(y, xh)) + 180.0
	var alt := rad_to_deg(atan2(zh, sqrt(xh * xh + y * y)))
	# az from north through east
	return Vector3(_sind(az) * _cosd(alt), _sind(alt), -_cosd(az) * _cosd(alt)).normalized()


func _place_bodies() -> void:
	var d := _day_number()
	var ecl := 23.4393 - 3.563e-7 * d
	# the sun
	var w := 282.9404 + 4.70935e-5 * d
	var e := 0.016709 - 1.151e-9 * d
	var m := _rev(356.0470 + 0.9856002585 * d)
	var ea := m + rad_to_deg(e) * _sind(m) * (1.0 + e * _cosd(m))
	var xv := _cosd(ea) - e
	var yv := sqrt(1.0 - e * e) * _sind(ea)
	var v := rad_to_deg(atan2(yv, xv))
	var lon_s := _rev(v + w)
	var xs := _cosd(lon_s)
	var ys := _sind(lon_s)
	var ra_s := rad_to_deg(atan2(ys * _cosd(ecl), xs))
	var dec_s := rad_to_deg(atan2(ys * _sind(ecl), sqrt(xs * xs + pow(ys * _cosd(ecl), 2.0))))
	var ls := _rev(m + w)
	var gmst0 := _rev(ls + 180.0) / 15.0
	var ut := hour - utc_offset
	var lst := gmst0 + ut + longitude / 15.0
	_sun = _sky_dir(ra_s, dec_s, lst)
	# the moon (geocentric, the biggest perturbations in longitude and latitude)
	var n := _rev(125.1228 - 0.0529538083 * d)
	var inc := 5.1454
	var wm := _rev(318.0634 + 0.1643573223 * d)
	var em := 0.054900
	var mm := _rev(115.3654 + 13.0649929509 * d)
	var eam := mm + rad_to_deg(em) * _sind(mm) * (1.0 + em * _cosd(mm))
	for _i in 3:
		eam = eam - (eam - rad_to_deg(em) * _sind(eam) - mm) / (1.0 - em * _cosd(eam))
	var xm := 60.2666 * (_cosd(eam) - em)
	var ym := 60.2666 * sqrt(1.0 - em * em) * _sind(eam)
	var vm := rad_to_deg(atan2(ym, xm))
	var rm := sqrt(xm * xm + ym * ym)
	var xe := rm * (_cosd(n) * _cosd(vm + wm) - _sind(n) * _sind(vm + wm) * _cosd(inc))
	var ye := rm * (_sind(n) * _cosd(vm + wm) + _cosd(n) * _sind(vm + wm) * _cosd(inc))
	var ze := rm * _sind(vm + wm) * _sind(inc)
	var lon_m := rad_to_deg(atan2(ye, xe))
	var lat_m := rad_to_deg(atan2(ze, sqrt(xe * xe + ye * ye)))
	var lm := _rev(n + wm + mm)
	var dm := lm - ls
	var f := lm - n
	lon_m += -1.274 * _sind(mm - 2.0 * dm) + 0.658 * _sind(2.0 * dm) - 0.186 * _sind(m) \
			- 0.059 * _sind(2.0 * mm - 2.0 * dm) - 0.057 * _sind(mm - 2.0 * dm + m) \
			+ 0.053 * _sind(mm + 2.0 * dm) + 0.046 * _sind(2.0 * dm - m)
	lat_m += -0.173 * _sind(f - 2.0 * dm) - 0.055 * _sind(mm - f - 2.0 * dm) \
			- 0.046 * _sind(mm + f - 2.0 * dm)
	var xg := _cosd(lon_m) * _cosd(lat_m)
	var yg := _sind(lon_m) * _cosd(lat_m)
	var zg := _sind(lat_m)
	var xq := xg
	var yq := yg * _cosd(ecl) - zg * _sind(ecl)
	var zq := yg * _sind(ecl) + zg * _cosd(ecl)
	_moon = _sky_dir(rad_to_deg(atan2(yq, xq)), rad_to_deg(atan2(zq, sqrt(xq * xq + yq * yq))), lst)


## Where the sun is, and the moon: unit vectors, x east, y up, z south.
func sun_direction() -> Vector3:
	return _sun


func moon_direction() -> Vector3:
	return _moon


## How much of the moon is lit, 0 new to 1 full.
func moon_phase() -> float:
	return (1.0 - _sun.dot(_moon)) * 0.5


# ------------------------------------------------------------------ the light

const R_PLANET := 6371000.0
const R_AIR := 6471000.0
const B_R := Vector3(5.5e-6, 13.0e-6, 22.4e-6)
const B_M := 21e-6
const H_R := 8000.0
const H_M := 1200.0
const SUN_I := 22.0


func _shell(r0: Vector3, rd: Vector3, r: float) -> Vector2:
	var b := rd.dot(r0)
	var c := r0.dot(r0) - r * r
	var dd := b * b - c
	if dd < 0.0:
		return Vector2(1e9, -1e9)
	dd = sqrt(dd)
	return Vector2(-b - dd, -b + dd)


func _exp3(v: Vector3) -> Vector3:
	return Vector3(exp(v.x), exp(v.y), exp(v.z))


## The sky shader's scattering, the same model, a few samples.
func _air(rd: Vector3, ps: Vector3, isun: float) -> Vector3:
	rd = Vector3(rd.x, maxf(rd.y, 0.012), rd.z).normalized()
	var r0 := Vector3(0.0, R_PLANET + ground_altitude + 2.0, 0.0)
	var p := _shell(r0, rd, R_AIR)
	p.x = maxf(p.x, 0.0)
	var ist := (p.y - p.x) / 8.0
	var it := p.x
	var trl := Vector3.ZERO
	var tmi := Vector3.ZERO
	var odr := 0.0
	var odm := 0.0
	var mu := rd.dot(ps)
	var gg := 0.76 * 0.76
	var prl := 3.0 / (16.0 * PI) * (1.0 + mu * mu)
	var pmi := 3.0 / (8.0 * PI) * ((1.0 - gg) * (mu * mu + 1.0)) / (pow(1.0 + gg - 2.0 * mu * 0.76, 1.5) * (2.0 + gg))
	for _i in 8:
		var ip := r0 + rd * (it + ist * 0.5)
		var ih := ip.length() - R_PLANET
		var sr := exp(-ih / H_R) * ist
		var sm := exp(-ih / H_M) * ist
		odr += sr
		odm += sm
		var jst := _shell(ip, ps, R_AIR).y / 3.0
		var jr := 0.0
		var jm := 0.0
		for j in 3:
			var jp := ip + ps * (jst * (float(j) + 0.5))
			var jh := jp.length() - R_PLANET
			jr += exp(-jh / H_R) * jst
			jm += exp(-jh / H_M) * jst
		var att := _exp3(-(Vector3.ONE * (B_M * (odm + jm)) + B_R * (odr + jr)))
		trl += sr * att
		tmi += sm * att
		it += ist
	return isun * (prl * B_R * trl + pmi * B_M * tmi)


## What the sun's light is when it reaches the ground: the air's transmittance
## along it.
func _sun_through(ps: Vector3) -> Vector3:
	if ps.y < -0.2:
		return Vector3.ZERO
	var r0 := Vector3(0.0, R_PLANET + ground_altitude + 2.0, 0.0)
	var g := _shell(r0, ps, R_PLANET)
	if g.x > 0.0:
		return Vector3.ZERO
	var l := _shell(r0, ps, R_AIR).y
	var odr := 0.0
	var odm := 0.0
	var st := l / 12.0
	for i in 12:
		var h := (r0 + ps * (st * (float(i) + 0.5))).length() - R_PLANET
		odr += exp(-h / H_R) * st
		odm += exp(-h / H_M) * st
	return _exp3(-(B_R * odr + Vector3.ONE * (B_M * 1.1 * odm)))


func _col(v: Vector3) -> Color:
	return Color(v.x, v.y, v.z)


## The island's light for the moment: what tod_* and the crowd are given.
func _island_light() -> Dictionary:
	var sun := _sun
	var up := Vector3.UP
	var side := Vector3(sun.x, 0.0, sun.z)
	side = side.normalized() if side.length_squared() > 1e-6 else Vector3.RIGHT
	var across := side.cross(Vector3.UP).normalized()
	var zen := _air(up, sun, SUN_I)
	var hor := _air((across + Vector3.UP * 0.035).normalized(), sun, SUN_I)
	var hor_sun := _air((side + Vector3.UP * 0.035).normalized(), sun, SUN_I)
	var trans := _sun_through(sun)
	var cover := float(_now.coverage)
	var shade := float(_now.shade)
	var light := float(_now.light)
	var gloom := float(_now.gloom)
	# the sun on the ground, dimmed by the clouds between
	var day := smoothstep(-0.12, 0.08, sun.y)
	var sun_g := trans * 1.12 * (1.0 - shade * smoothstep(0.1, 0.9, cover)) * light
	# the sky's light: the zenith's, half way to grey (the whole dome lights
	# the ground, not its bluest point), greyer still under cloud; scaled so a
	# clear noon gives the island the ambient its own islands are lit by
	var sky := zen * 2.0 * (1.0 - 0.35 * gloom)
	var lum := sky.dot(Vector3(0.3, 0.5, 0.2))
	sky = sky.lerp(Vector3.ONE * lum, 0.5) * 1.2
	sky = sky.lerp(Vector3.ONE * lum * 1.25, clampf(cover * 0.9, 0.0, 1.0)) * light
	# at night, the moon's
	var moon := _moon
	var phase := moon_phase()
	var moon_up := smoothstep(-0.05, 0.1, moon.y) * (1.0 - day)
	# (a playable night, as Enviro's are: dark blue, never black; the moon
	# lighting it as far again when it is full and up)
	var moon_c := Vector3(0.16, 0.19, 0.27) * (0.25 + 0.75 * phase) * moon_up * (1.0 - 0.7 * cover)
	var night := (Vector3(0.05, 0.065, 0.11) + moon_c * 0.4) * (1.0 - day)
	sky += night
	var use_moon := sun.y < -0.06 and moon.y > 0.0
	var light_dir := moon if use_moon else sun
	var light_col := moon_c if use_moon else sun_g * smoothstep(-0.05, 0.03, sun.y)
	# the bounce off the ground: its light, earth-coloured
	var bounce := (light_col * maxf(light_dir.y, 0.0) * 0.3 + sky * 0.45) * Vector3(0.62, 0.56, 0.48)
	# the horizon's colour, what the fog fades into: half the island's own fog
	# colour at the air's brightness, half the air's own (its sunset reds), no
	# brighter than a pale haze
	var raw := hor * 0.65 + hor_sun * 0.35
	var rl := raw.dot(Vector3(0.3, 0.5, 0.2))
	var fb := Vector3(fog_base.r, fog_base.g, fog_base.b)
	var horizon := (fb * rl / 0.62).lerp(raw, 0.5)
	var hl := horizon.dot(Vector3(0.3, 0.5, 0.2))
	if hl > 0.8:
		horizon *= 0.8 / hl
	horizon = horizon.lerp(Vector3.ONE * horizon.dot(Vector3(0.3, 0.5, 0.2)) * 1.1, cover * 0.7)
	# under a heavy sky the air far off is as dark as the light under it
	horizon *= light * (1.0 - 0.5 * gloom)
	var hz := float(_now.haze)
	var hc: Color = _now.haze_color
	var dayish := clampf(day + moon_up * 0.15, 0.04, 1.0)
	horizon = horizon.lerp(Vector3(hc.r, hc.g, hc.b) * dayish * light, hz)
	horizon += Vector3(0.04, 0.05, 0.085) * (1.0 - day)
	return {"sun_dir": light_dir, "sun": light_col, "sky": sky, "ground": bounce,
		"horizon": horizon, "day": day, "zenith": zen, "sun_cloud": trans * light,
		"moon_light": phase * moon_up}


func _push_globals() -> void:
	if _light.is_empty():
		return
	var L := _light
	var fl := _flash
	RenderingServer.global_shader_parameter_set("tod_sun_dir", L.sun_dir)
	RenderingServer.global_shader_parameter_set("tod_sun_color", _col(L.sun + Vector3.ONE * fl * 0.6))
	RenderingServer.global_shader_parameter_set("tod_sky_color", _col(L.sky + Vector3(0.8, 0.85, 1.0) * fl))
	RenderingServer.global_shader_parameter_set("tod_ground_color", _col(L.ground))
	var hz: Vector3 = L.horizon
	var tint := Color(hz.x / fog_base.r, hz.y / fog_base.g, hz.z / fog_base.b)
	RenderingServer.global_shader_parameter_set("tod_haze_tint", tint)
	# the plants and the water are unlit: one tint for the light on them
	var lv: Vector3 = L.sun * 0.55 * maxf(L.sun_dir.y, 0.15) + L.sky * 1.2
	var lum := lv.dot(Vector3(0.3, 0.5, 0.2))
	# its hue, at the brightness noon's light is given as 1
	var tv := lv / maxf(lum, 1e-4) * clampf(lum / 0.95, 0.0, 1.2)
	var art := Color(clampf(tv.x + fl, 0.0, 2.0), clampf(tv.y + fl, 0.0, 2.0), clampf(tv.z + fl, 0.0, 2.0))
	RenderingServer.global_shader_parameter_set("tod_art_tint", art)
	_art = art
	RenderingServer.global_shader_parameter_set("tod_water_tint", art)
	RenderingServer.global_shader_parameter_set("tod_daylight", float(L.day))
	RenderingServer.global_shader_parameter_set("tod_env_blend", 1.0 - float(L.day))
	RenderingServer.global_shader_parameter_set("tod_fog_density", float(_now.fog_density))
	RenderingServer.global_shader_parameter_set("tod_fog_near", float(_now.fog_near))
	var we := get_node_or_null(world_environment) as WorldEnvironment
	if we != null and we.environment != null:
		we.environment.ambient_light_color = _col(L.sky)
		we.environment.ambient_light_energy = 1.0


## For the crowd, the gore and the sparks (Game._island_light): how lit the
## world is, the floor under that, and the colour the air goes far off.
func world_light() -> Dictionary:
	if _light.is_empty():
		return {}
	var L := _light
	var lv: Vector3 = L.sun * maxf(L.sun_dir.y, 0.0) * 0.6 + L.sky
	var level := clampf(lv.dot(Vector3(0.3, 0.5, 0.2)) / 0.8, 0.06, 1.0)
	var hz: Vector3 = L.horizon
	return {"sky_light": level, "min_light": clampf(level * 0.85, 0.05, 0.85),
		"air_color": Color(hz.x, hz.y, hz.z), "air_near": 700.0 / maxf(float(_now.fog_density), 0.2),
		"air_far": 3200.0 / maxf(float(_now.fog_density), 0.2)}


func _push_sky() -> void:
	var m := sky_material
	if m == null or _light.is_empty():
		return
	var top := ground_top + float(_now.base)
	m.set_shader_parameter("sun_dir", _sun)
	m.set_shader_parameter("moon_dir", _moon)
	m.set_shader_parameter("moon_light", float(_light.moon_light))
	m.set_shader_parameter("ground_altitude", ground_altitude)
	m.set_shader_parameter("stars", 1.0)
	m.set_shader_parameter("coverage", float(_now.coverage))
	m.set_shader_parameter("density", float(_now.density))
	m.set_shader_parameter("cloud_type", float(_now.cloud_type))
	m.set_shader_parameter("cloud_bottom", top)
	m.set_shader_parameter("cloud_top", top + float(_now.thickness))
	m.set_shader_parameter("cirrus", float(_now.cirrus))
	m.set_shader_parameter("gloom", float(_now.gloom))
	m.set_shader_parameter("haze", float(_now.haze))
	var hc: Color = _now.haze_color
	var day: float = _light.day
	m.set_shader_parameter("haze_color", Color(hc.r * maxf(day, 0.05), hc.g * maxf(day, 0.05), hc.b * maxf(day, 0.06)))
	m.set_shader_parameter("wind_offset", _wind_off)
	m.set_shader_parameter("cirrus_offset", _cirrus_off)
	# the light the clouds take: the sun through the air, a little of the moon
	var sc: Vector3 = _light.sun_cloud * smoothstep(-0.08, 0.02, _sun.y) + Vector3(0.6, 0.65, 0.8) * float(_light.moon_light) * 0.25
	m.set_shader_parameter("cloud_sun", _col(sc * 1.1 + Vector3.ONE * _flash * 2.0))
	var zen: Vector3 = _light.zenith
	var hz: Vector3 = _light.horizon
	var dim := 1.0 - 0.5 * float(_now.gloom)
	m.set_shader_parameter("cloud_ambient_top", _col((zen * 2.0 + hz * 0.12) * dim + Vector3(0.03, 0.035, 0.06)))
	m.set_shader_parameter("cloud_ambient_bottom", _col(hz * 0.35 * dim + Vector3(0.015, 0.018, 0.03)))
	m.set_shader_parameter("flash", _flash)
	m.set_shader_parameter("bolt", _bolt)


# ------------------------------------------------------------------ storms

func _storm(dt: float) -> void:
	_flash = maxf(_flash - dt * 6.0, 0.0)
	_bolt = maxf(_bolt - dt * 5.0, 0.0)
	var rate := float(_now.get("lightning", 0.0))
	if rate <= 0.05 or sky_material == null:
		return
	_next_strike -= dt
	if _next_strike <= 0.0:
		_next_strike = randf_range(0.4, 2.0) * 60.0 / rate
		_flash = randf_range(0.6, 1.0)
		_bolt = 1.0
		var a := randf() * TAU
		sky_material.set_shader_parameter("bolt_dir", Vector3(cos(a), 0.15, sin(a)).normalized())
		sky_material.set_shader_parameter("bolt_seed", randf() * 100.0)


# ------------------------------------------------------------------ what falls

func _make_falls() -> void:
	_rain = _falling(Color(0.66, 0.7, 0.76, 0.16), Vector2(0.018, 0.55), 2400, 1.3, Vector3(0, -11.0, 0))
	_snow = _falling(Color(0.95, 0.96, 1.0, 0.85), Vector2(0.07, 0.07), 3000, 9.0, Vector3(0, -1.3, 0))
	_rain.set_meta("base", Color(0.66, 0.7, 0.76, 0.16))
	_snow.set_meta("base", Color(0.95, 0.96, 1.0, 0.85))
	add_child(_rain)
	add_child(_snow)


func _falling(c: Color, size: Vector2, amount: int, life: float, vel: Vector3) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	var q := QuadMesh.new()
	q.size = size
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = c
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	q.material = mat
	p.draw_pass_1 = q
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(30.0, 8.0, 30.0)
	pm.direction = vel.normalized()
	pm.spread = 4.0
	pm.initial_velocity_min = vel.length() * 0.85
	pm.initial_velocity_max = vel.length() * 1.15
	pm.gravity = Vector3.ZERO
	p.process_material = pm
	p.amount = amount
	p.lifetime = life
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-40.0, -40.0, -40.0), Vector3(80.0, 60.0, 80.0))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.emitting = false
	return p


func _push_falls() -> void:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null:
		return
	var wf := deg_to_rad(float(_now.wind_from))
	var blow := -Vector3(sin(wf), 0.0, -cos(wf)) * float(_now.wind)
	for pair in [[_rain, float(_now.rain)], [_snow, float(_now.snow)]]:
		var p: GPUParticles3D = pair[0]
		var amt: float = pair[1]
		if p == null:
			continue
		p.emitting = amt > 0.02
		p.amount_ratio = clampf(amt, 0.0, 1.0)
		# unlit, so lit here: as dark as the light under the clouds
		var base: Color = p.get_meta("base")
		var mat := (p.draw_pass_1 as QuadMesh).material as StandardMaterial3D
		mat.albedo_color = Color(base.r * _art.r, base.g * _art.g, base.b * _art.b, base.a)
		p.global_position = cam.global_position + Vector3(0.0, 18.0, 0.0) - blow * 0.6
		# the wind leans it (less for the rain, which is fast)
		var lean := 0.25 if p == _rain else 0.6
		(p.process_material as ParticleProcessMaterial).direction = (Vector3(0.0, -1.0, 0.0) + blow * lean / 10.0).normalized()
