class_name MapView
extends Control

## THE WORLD, FLAT, TO PICK A PLACE ON (WorldMap's): the AWS Terrain Tiles as
## a shaded relief (map_relief.gdshader), Web Mercator, zoom 2 to 14, fetched
## on worker threads through GeoFetch (so they are cached on disk as the
## region builder's are); dragged to pan, the wheel to zoom about the mouse;
## a square the size of the place to be built under the mouse, and a click
## to choose it. The places already built are drawn where they are.

signal picked(lat: float, lon: float)
signal moved

const TILE_URL := "https://s3.amazonaws.com/elevation-tiles-prod/terrarium/%d/%d/%d.png"
const MIN_Z := 2.0
const MAX_Z := 14.0
const EARTH := 40075016.686
const MOST_TILES := 700
const IN_FLIGHT := 8

## the view: its zoom, and its middle in Web Mercator (0..1 across and down)
var zoom := 3.0
var centre := Vector2(0.53, 0.36)
## the square to build, metres a side
var square_m := 3000.0
## the chosen square's middle (lat, lon), NAN none
var chosen := Vector2(NAN, NAN)
## [{lat, lon, size, title}] drawn as markers
var places: Array = []

var _tiles := {}
var _order: Array = []
var _queue: Array = []
var _flying := 0
var _drag := false
var _drag_from := Vector2.ZERO
var _dragged := 0.0
var _hover := Vector2(-1, -1)
var _font: Font
# the squares, the markers and the words, drawn over the relief without its
# shader (which would read their colours as heights)
var _overlay: Control


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var m := ShaderMaterial.new()
	m.shader = preload("res://godot/shaders/map_relief.gdshader")
	material = m
	_font = U.ui_font(false)
	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)


## Draw it all again.
func redraw() -> void:
	queue_redraw()
	if _overlay != null:
		_overlay.queue_redraw()


## Look at (lat, lon) at this zoom.
func look_at_place(lat: float, lon: float, z := -1.0) -> void:
	centre = merc(lat, lon)
	if z > 0.0:
		zoom = clampf(z, MIN_Z, MAX_Z)
	redraw()
	moved.emit()


## (lat, lon) to Web Mercator 0..1.
static func merc(lat: float, lon: float) -> Vector2:
	var p := deg_to_rad(clampf(lat, -85.05, 85.05))
	return Vector2((lon + 180.0) / 360.0, (1.0 - log(tan(p) + 1.0 / cos(p)) / PI) / 2.0)


## Web Mercator 0..1 to (lat, lon).
static func unmerc(m: Vector2) -> Vector2:
	var lat := rad_to_deg(atan(sinh(PI * (1.0 - 2.0 * m.y))))
	return Vector2(lat, m.x * 360.0 - 180.0)


func _world_px() -> float:
	return 256.0 * pow(2.0, zoom)


func to_screen(m: Vector2) -> Vector2:
	return (m - centre) * _world_px() + size * 0.5


func to_merc(p: Vector2) -> Vector2:
	return centre + (p - size * 0.5) / _world_px()


## Metres a screen pixel spans at latitude `lat`.
func metres_per_px(lat: float) -> float:
	return EARTH * cos(deg_to_rad(lat)) / _world_px()


func _draw() -> void:
	var tz := int(clampf(roundf(zoom), MIN_Z, MAX_Z))
	var n := 1 << tz
	var tile_px := _world_px() / n
	var tl := to_merc(Vector2.ZERO) * n
	var br := to_merc(size) * n
	var mid_lat := unmerc(centre).x
	(material as ShaderMaterial).set_shader_parameter("metres_per_texel",
			EARTH * cos(deg_to_rad(mid_lat)) / (256.0 * n))
	for ty in range(maxi(int(floor(tl.y)), 0), mini(int(floor(br.y)), n - 1) + 1):
		for tx in range(int(floor(tl.x)), int(floor(br.x)) + 1):
			var pos := to_screen(Vector2(tx, ty) / n)
			var rect := Rect2(pos, Vector2(tile_px, tile_px))
			var tex := _tile(tz, posmod(tx, n), ty)
			if tex != null:
				draw_texture_rect(tex, rect, false)
				continue
			# (the coarser tile over it while it comes, the part of it that is this one)
			for up in range(1, 5):
				var pz := tz - up
				if pz < 0:
					break
				var k := 1 << up
				var pt := _tile(pz, posmod(tx, n) / k, ty / k, false)
				if pt != null:
					var sub := 256.0 / k
					var src := Rect2(Vector2(posmod(tx, n) % k, ty % k) * sub, Vector2(sub, sub))
					draw_texture_rect_region(pt, rect, src)
					break


func _draw_overlay() -> void:
	var o := _overlay
	# the places already built
	for p in places:
		var c := to_screen(merc(float(p.lat), float(p.lon)))
		var half := float(p.size) * 0.5 / metres_per_px(float(p.lat))
		if half >= 3.0:
			o.draw_rect(Rect2(c - Vector2(half, half), Vector2(half, half) * 2.0), Color(0.55, 0.9, 1.0, 0.9), false, 1.5)
		else:
			o.draw_circle(c, 4.0, Color(0.55, 0.9, 1.0, 0.9))
		o.draw_string(_font, c + Vector2(half + 6.0, 4.0), String(p.title), HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
				Color(0.85, 0.97, 1.0))
	# the square under the mouse, and the chosen one
	if _hover.x >= 0.0 and not _drag:
		var ll := unmerc(to_merc(_hover))
		var half := square_m * 0.5 / metres_per_px(ll.x)
		o.draw_rect(Rect2(_hover - Vector2(half, half), Vector2(half, half) * 2.0), Color(1, 1, 1, 0.55), false, 1.0)
	if not is_nan(chosen.x):
		var c := to_screen(merc(chosen.x, chosen.y))
		var half := maxf(square_m * 0.5 / metres_per_px(chosen.x), 3.0)
		o.draw_rect(Rect2(c - Vector2(half, half), Vector2(half, half) * 2.0), Color(1.0, 0.82, 0.25), false, 2.0)
	# where the mouse is
	if _hover.x >= 0.0:
		var ll := unmerc(to_merc(_hover))
		o.draw_string(_font, Vector2(10, size.y - 10), "%.4f %s  %.4f %s   zoom %.1f" % [absf(ll.x),
				"N" if ll.x >= 0.0 else "S", absf(ll.y), "E" if ll.y >= 0.0 else "W", zoom],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.9))


# the tile's texture, or null — asked for when `fetch` and not there yet
func _tile(z: int, x: int, y: int, fetch := true) -> Texture2D:
	var key := Vector3i(z, x, y)
	if _tiles.has(key):
		return _tiles[key]
	if fetch and not _queue.has(key):
		_queue.append(key)
		_pump.call_deferred()
	return null


func _pump() -> void:
	while _flying < IN_FLIGHT and not _queue.is_empty():
		# (the newest asked first: what is on screen now)
		var key: Vector3i = _queue.pop_back()
		if _tiles.has(key):
			continue
		_tiles[key] = null
		_flying += 1
		# (handed back only to a map still there: one closed while a tile was
		# on its way is not)
		var me: WeakRef = weakref(self)
		WorkerThreadPool.add_task(func():
			var r := GeoFetch.get_url(TILE_URL % [key.x, key.y, key.z])
			var still: Object = me.get_ref()
			if still != null:
				still.call_deferred("_arrived", key, r.body if r.ok else PackedByteArray()), false, "map tile")
	if _queue.size() > 64:
		_queue = _queue.slice(_queue.size() - 64)


func _arrived(key: Vector3i, body: PackedByteArray) -> void:
	_flying -= 1
	var img := Image.new()
	if not body.is_empty() and img.load_png_from_buffer(body) == OK:
		_tiles[key] = ImageTexture.create_from_image(img)
		_order.append(key)
		while _order.size() > MOST_TILES:
			_tiles.erase(_order.pop_front())
	else:
		_tiles.erase(key)
	redraw()
	_pump()


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		var mb := e as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_drag = true
				_drag_from = mb.position
				_dragged = 0.0
				grab_focus()
			else:
				_drag = false
				if _dragged < 5.0:
					var ll := unmerc(to_merc(mb.position))
					chosen = ll
					picked.emit(ll.x, ll.y)
				redraw()
		elif mb.pressed and mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			_zoom_about(mb.position, 0.25 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else -0.25)
		accept_event()
	elif e is InputEventMouseMotion:
		var mm := e as InputEventMouseMotion
		_hover = mm.position
		if _drag:
			_dragged += mm.relative.length()
			centre -= mm.relative / _world_px()
			centre.y = clampf(centre.y, 0.0, 1.0)
			moved.emit()
		redraw()
	elif e is InputEventMagnifyGesture:
		_zoom_about((e as InputEventMagnifyGesture).position, log((e as InputEventMagnifyGesture).factor) / log(2.0))
	elif e is InputEventKey and e.pressed:
		var step := 120.0 / _world_px()
		match (e as InputEventKey).keycode:
			KEY_EQUAL, KEY_KP_ADD:
				_zoom_about(size * 0.5, 0.5)
			KEY_MINUS, KEY_KP_SUBTRACT:
				_zoom_about(size * 0.5, -0.5)
			KEY_LEFT:
				centre.x -= step
			KEY_RIGHT:
				centre.x += step
			KEY_UP:
				centre.y = maxf(centre.y - step, 0.0)
			KEY_DOWN:
				centre.y = minf(centre.y + step, 1.0)
		redraw()
		moved.emit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		_hover = Vector2(-1, -1)
		redraw()


func _zoom_about(p: Vector2, dz: float) -> void:
	var at := to_merc(p)
	zoom = clampf(zoom + dz, MIN_Z, MAX_Z)
	centre = at - (p - size * 0.5) / _world_px()
	redraw()
	moved.emit()
