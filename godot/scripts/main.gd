## FENRIR, THE TERRAIN ENGINE: a place drawn by the chunked island system
## (godot/island/) — a real one made out of open map data (tools/earth_fetch.py)
## or golf's procedural island — with its sky, its water, its plants and its
## light, the cinema over it, and a camera to fly round it. That is the app.
##
## On the command line, after `--`:
##   --map=KEY                   the place (Islands.LIST; the first if none)
##   --at=X,Z  --high=M          where the eye starts, metres east and south
##                               of the middle, and how high over the ground
##   --y=Y                       or at this height in the world (metres)
##   --face=X,Z | --turn=DEG | --look=sun|moon [--look-off=DEG,DEG]
##   --pitch=DEG                 the eye's look up (+) or down (-)
##   --walk                      on the ground, not flying
##   --retro                     the 360-row pixel picture
##   --cine=NAME:VALUE,... | --cine=off   the cinema pass's numbers
##   --sky-hour=H --sky-day=D --sky-weather=ID --sky-minutes=M   (EnviroSky)
##   --shot=PATH [--frames=N]    a picture once the place is up (and N more
##                               frames), then quit
extends Node

const WEATHERS := ["clear", "fair", "partly_cloudy", "cloudy", "overcast", "foggy",
	"light_rain", "rain", "storm", "light_snow", "snow"]

var lofi: Lofi
var hud: ViewerHud
## the world map's window (WorldMap), or null
var world_map: WorldMap = null
var cam: FlyCamera
var place: Node3D = null
var spec: Dictionary = {}
var field: IslandField = null
var _isl: IslandField.Island = null
var _built := false
var _placed := false
var _up_frames := -1
var _shot := ""
var _frames := 30
var _args := PackedStringArray()
## a built place's bakes: 0 nothing to do, 1 to save once it is up, 2 saving
var _save_bake := 0


func _ready() -> void:
	_args = OS.get_cmdline_user_args()
	lofi = Lofi.new()
	add_child(lofi)
	lofi.set_retro(_has("--retro"))
	hud = ViewerHud.new()
	add_child(hud)
	_shot = _val("--shot=", "")
	_frames = int(_val("--frames=", "30"))
	if _shot != "":
		hud.set_clean(true)
	load_place(_val("--map=", String(Islands.LIST[0].key)))
	# THE WORLD MAP, a window of its own beside this one, on a desktop with a
	# screen (not for a picture taken on the command line, or the tests)
	if _shot == "" and not _has("--no-map") and DisplayServer.get_name() != "headless" \
			and not OS.has_feature("android"):
		world_map = WorldMap.new()
		world_map.fly.connect(_on_fly)
		add_child(world_map)
		world_map.map.look_at_place(float(spec.get("lat", 46.5)), float(spec.get("lon", 7.7)), 5.0)
		world_map.show()


## A place picked or built on the world map: flown to here.
func _on_fly(key: String) -> void:
	load_place(key)
	get_window().grab_focus()


func _has(flag: String) -> bool:
	return flag in _args


func _val(prefix: String, fallback: String) -> String:
	for a in _args:
		if a.begins_with(prefix):
			return a.substr(prefix.length())
	return fallback


func _vec(s: String) -> Vector2:
	var p := s.split(",")
	return Vector2(float(p[0]), float(p[1])) if p.size() >= 2 else Vector2.ZERO


## Load the place called `key`, in place of whatever was there.
func load_place(key: String) -> void:
	# (out of the tree at once, so the old place's own goodbyes — its
	# shadows' and water's globals switched off — come before the new one's)
	if place != null:
		place.get_parent().remove_child(place)
		place.queue_free()
		place = null
	if cam != null:
		cam.get_parent().remove_child(cam)
		cam.queue_free()
	spec = Islands.find(key)
	_built = false
	_placed = false
	_up_frames = -1
	# the eye first, so the island streams round it from its first frame
	cam = FlyCamera.new()
	cam.name = "Eye"
	lofi.world.add_child(cam)
	cam.make_current()
	cam.ground = _ground
	cam.walking = _has("--walk")
	var scene := (load(spec.scene) as PackedScene).instantiate() as Node3D
	var iw0 := scene.get_node_or_null("IslandWorld")
	_save_bake = 0
	if spec.has("region") and iw0 != null:
		# A PLACE BUILT HERE (the world map, Regions): the real-place template
		# with its field pointed at the region's folder, and its meshes and
		# plants kept as they are built, to be saved for the next visit
		var fld := (iw0.get("field") as Resource).duplicate()
		fld.set("region", String(spec.region))
		# (the island is the square: as wide as the place, not the template's)
		fld.set("hub_radius", float(spec.get("size", 3000.0)) * 0.5)
		iw0.set("field", fld)
		TerrainBake.record_arrays = true
		_save_bake = 1
	var sky := scene.get_node_or_null("EnviroSky")
	if sky != null:
		sky.set("options", spec.get("sky", {}))
	var iw := scene.get_node_or_null("IslandWorld")
	if iw != null:
		iw.connect("pregen_finished", func(): _built = true)
		# (how far the building has got, under the badge: a place built here
		# and seen for the first time builds every chunk of it, a minute or so)
		iw.connect("pregen_progress", func(stage: String, done: int, total: int):
			if total > 0 and _save_bake < 2:
				hud.loading.text = "%s\nbuilding the place... %d%%" % [spec.title, roundi(100.0 * done / total)])
	place = scene
	lofi.world.add_child(scene)
	field = iw.get("field") as IslandField if iw != null else null
	if field != null:
		field.prepare()
		_isl = field.island_in_cell(field.hub_cell())
	else:
		_built = true
	lofi.for_island(spec)
	# the cinema's numbers off the command line, for tuning
	var cine := scene.get_node_or_null("Cinema") as MeshInstance3D
	var ca := _val("--cine=", "")
	if cine != null and ca != "":
		if ca == "off":
			cine.visible = false
		else:
			for kv in ca.split(","):
				var parts := kv.split(":")
				if parts.size() == 2:
					(cine.material_override as ShaderMaterial).set_shader_parameter(parts[0], float(parts[1]))
	_place_eye()
	hud.loading.text = "%s\nbuilding the place..." % spec.title
	get_window().title = "FENRIR — %s" % spec.title
	# (nothing drawn while it builds: the building is paced by the frame, and
	# a frame with the whole place in it is many times one without)
	lofi.world.render_target_update_mode = SubViewport.UPDATE_DISABLED


## A PLACE BUILT HERE, UP FOR THE FIRST TIME: its terrain's and its plants'
## bakes written to user://bake (BakeStore.READ_DIRS), so the next visit reads
## them instead of building it all again. True when done (the place may come
## up); the first call only says so on the screen.
func _save_bakes() -> bool:
	var iw := place.get_node_or_null("IslandWorld")
	if _save_bake == 1:
		if iw != null and String(iw.get("bake_source")) != "":
			_save_bake = 0
			TerrainBake.record_arrays = false
			return true
		_save_bake = 2
		hud.loading.text = "%s\nsaving the place for next time..." % spec.title
		return false
	_save_bake = 0
	for store in [TerrainBake, VegBake]:
		var st: Dictionary = store.stats()
		if int(st.held) == 0 or String(st.signature) == "":
			continue
		var path := "user://bake/%s" % BakeStore.file_name(store.STORE_NAME, String(st.signature))
		var n: int = store.save_to(path)
		print("FENRIR: %s bake: %d entries -> %s" % [store.STORE_NAME, n, ProjectSettings.globalize_path(path)])
	TerrainBake.record_arrays = false
	return true


## The ground under (x, z), metres (under the water too), or NAN off the land.
func _ground(x: float, z: float) -> float:
	if field == null or _isl == null:
		return NAN
	var h := field.landform_height(_isl, x, z, NAN)
	return h


## Where the eye starts: the command line's, or the island's "start".
func _place_eye() -> void:
	var at: Vector2 = spec.get("start", Vector2.ZERO)
	if _val("--at=", "") != "":
		at = _vec(_val("--at=", ""))
	var high := float(_val("--high=", "1.7" if cam.walking else str(spec.get("start_high", 6.0))))
	var g := _ground(at.x, at.y)
	if is_nan(g):
		g = 0.0
	cam.global_position = Vector3(at.x, g + high, at.y)
	if _val("--y=", "") != "":
		cam.global_position.y = float(_val("--y=", "0"))
	var face: Variant = spec.get("start_face", null)
	if _val("--face=", "") != "":
		face = _vec(_val("--face=", ""))
	if face != null:
		var f: Vector2 = face
		cam.face_point(Vector3(f.x, cam.global_position.y, f.y))
	if _val("--turn=", "") != "":
		cam.yaw = deg_to_rad(float(_val("--turn=", "0")) - 90.0)
	if _val("--pitch=", "") != "":
		cam.pitch = deg_to_rad(float(_val("--pitch=", "0")))
	cam._apply()
	cam.eye_height = high if cam.walking else cam.eye_height


## The eye at the sun or the moon (--look=), a little off it (--look-off=).
func _look_at_sky() -> void:
	var look := _val("--look=", "")
	var sky := _sky()
	if look == "" or sky == null:
		return
	var v: Vector3 = sky.sun_direction() if look == "sun" else sky.moon_direction()
	cam.yaw = atan2(-v.x, -v.z)
	cam.pitch = asin(clampf(v.y, -1.0, 1.0))
	if _val("--look-off=", "") != "":
		var o := _vec(_val("--look-off=", ""))
		cam.yaw += deg_to_rad(o.x)
		cam.pitch -= deg_to_rad(o.y)
	cam._apply()


func _sky() -> Node:
	return place.get_node_or_null("EnviroSky") if place != null else null


## The place is up: its terrain built (or read off the bake), its plants
## planted and the grass round the eye down.
func place_ready() -> bool:
	if place == null or not _built:
		return false
	var vs := place.get_node_or_null("VegScatter")
	if vs != null and not bool(vs.get("_prescattered")):
		return false
	for n in place.get_children():
		if n.has_method("filled") and not n.filled():
			return false
	return true


func _process(dt: float) -> void:
	if place == null:
		return
	if not _placed and field != null:
		_place_eye()
		_look_at_sky()
		_placed = true
	# (up once, up for good: the grass streaming in round a moving eye is
	# not a place being built — a new place, load_place, starts it over)
	var up := _up_frames >= 0 or place_ready()
	# (a place built here and come up without a bake: its bakes saved first,
	# a frame after saying so, so the next visit starts at once)
	if up and _up_frames < 0 and _save_bake > 0:
		up = _save_bakes()
	hud.set_loading(not up)
	# THE METER (Lofi): nothing to read until the place is drawn; then its
	# first readings taken whole, and after that eased to, as an eye adapts
	# (a twentieth a frame at 60 frames a second: about a second)
	if not up:
		lofi.set_meter_rate(-1.0)
	else:
		lofi.set_meter_rate(1.0 if _up_frames < 6 else 1.0 - exp(-dt * 3.0))
	if up and _up_frames < 0:
		_up_frames = 0
		lofi.world.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		# (and the mountains' shadows baked again now the world draws)
		var es := place.get_node_or_null("EarthSun")
		if es != null and es.has_method("_rebake"):
			es.call("_rebake")
		print("FENRIR: %s is up" % spec.title)
	elif up:
		_up_frames += 1
	# (the eye kept at the sun while a shot waits on the place)
	if _shot != "" and _val("--look=", "") != "":
		_look_at_sky()
	if _shot != "" and _up_frames >= _frames:
		_take_shot()
	if hud.show_info:
		hud.info.text = _readout()


func _take_shot() -> void:
	set_process(false)
	await RenderingServer.frame_post_draw
	get_tree().root.get_texture().get_image().save_png(_shot)
	print("FENRIR: %s at %.0f, %.0f, %.0f m up" % [_shot, cam.global_position.x, cam.global_position.z,
		cam.global_position.y - (_ground(cam.global_position.x, cam.global_position.z) if field else 0.0)])
	get_tree().quit()


func _readout() -> String:
	var p := cam.global_position
	var g := _ground(p.x, p.z)
	var lines := ["%s" % spec.title]
	var datum := 0.0
	if field is EarthField:
		datum = (field as EarthField).data().datum
	lines.append("%+.0f E  %+.0f S   %.0f m over sea, %.0f m over the ground" % [p.x, p.z, p.y + datum,
		p.y - g if not is_nan(g) else 0.0])
	var sky := _sky()
	if sky != null:
		var h := float(sky.get("hour"))
		lines.append("%02d:%02d  %s%s" % [int(h), int(fmod(h, 1.0) * 60.0), String(sky.get("weather")).replace("_", " "),
			"  (the clock runs)" if float(sky.get("day_minutes")) > 0.0 else ""])
	lines.append("%s  %.0f m/s   %d fps   H keys" % ["walking" if cam.walking else "flying", cam.speed,
		Engine.get_frames_per_second()])
	return "\n".join(lines)


func _unhandled_input(e: InputEvent) -> void:
	# (the eye is in the picture's world, which no input reaches by itself)
	if cam != null:
		cam.handle(e)
	if not (e is InputEventKey and e.pressed and not e.echo):
		return
	var sky := _sky()
	match e.keycode:
		KEY_H:
			hud.help.visible = not hud.help.visible
		KEY_M:
			if world_map != null:
				world_map.visible = not world_map.visible
				if world_map.visible:
					world_map.grab_focus()
		KEY_I:
			hud.set_clean(hud.show_info)
		KEY_P:
			lofi.set_retro(not lofi.is_retro())
		KEY_K:
			var cine := place.get_node_or_null("Cinema") as Node3D if place else null
			if cine != null:
				cine.visible = not cine.visible
		KEY_B:
			var edge := place.get_node_or_null("EdgeField") as Node3D if place else null
			if edge != null:
				edge.visible = not edge.visible
		KEY_N:
			var i := 0
			var places := Islands.all()
			for k in places.size():
				if places[k].key == spec.key:
					i = k
			load_place(String(places[(i + 1) % places.size()].key))
		KEY_BRACKETLEFT, KEY_BRACKETRIGHT:
			if sky != null:
				var step := (1.0 if e.shift_pressed else 0.25) * (1.0 if e.keycode == KEY_BRACKETRIGHT else -1.0)
				sky.set("hour", fposmod(float(sky.get("hour")) + step, 24.0))
		KEY_T:
			if sky != null:
				sky.set("day_minutes", 0.0 if float(sky.get("day_minutes")) > 0.0 else 4.0)
		KEY_F:
			if sky != null:
				var w := WEATHERS.find(String(sky.get("weather")))
				sky.call("set_weather", WEATHERS[(w + 1) % WEATHERS.size()])
		KEY_F12:
			var path := "user://fenrir_%s.png" % Time.get_datetime_string_from_system().replace(":", "-")
			get_tree().root.get_texture().get_image().save_png(path)
			print("FENRIR: %s" % ProjectSettings.globalize_path(path))
