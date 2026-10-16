class_name WorldMap
extends Window

## THE PLANET, TO PICK A PLACE ON (at the user's request: "we need to have a
## planet-wide selector (2D) where you select the area you want to render in
## 3D, and then it renders it", "keep it inside the app, linux only, separate
## windows if possible"): a window of its own beside the 3D one — the world
## as a shaded relief (MapView) with a square the size of the place under the
## mouse; a search for a place by its name (OpenStreetMap's Nominatim) or by
## its "lat, lon"; the square's size; and BUILD & FLY, which makes the place
## here (RegionBuilder, on a thread of its own, its progress on the bar) and
## hands it to the viewer to fly (`fly`). The places already built are on the
## map and in a list, to fly to again at once.

signal fly(key: String)

const NOMINATIM := "https://nominatim.openstreetmap.org/search?format=json&limit=1&q=%s"

var map: MapView
var _search: LineEdit
var _size: HSlider
var _size_label: Label
var _title: LineEdit
var _where: Label
var _build: Button
var _cancel: Button
var _bar: ProgressBar
var _status: Label
var _list: ItemList
var _places: Array = []
var _builder: RegionBuilder = null
var _thread: Thread = null
var _name := ""
var _found_title := ""


func _init() -> void:
	title = "FENRIR — the world"
	size = Vector2i(1180, 740)
	min_size = Vector2i(760, 480)
	wrap_controls = false
	close_requested.connect(hide)
	var font := U.ui_font(false)
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.07, 0.1)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", 0)
	add_child(row)
	map = MapView.new()
	map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map.picked.connect(_on_picked)
	row.add_child(map)
	var side := PanelContainer.new()
	side.custom_minimum_size = Vector2(320, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.1, 0.13)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 14
	sb.content_margin_bottom = 14
	side.add_theme_stylebox_override("panel", sb)
	row.add_child(side)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	side.add_child(col)
	var badge := TextureRect.new()
	badge.texture = preload("res://godot/data/brand/fenrir_logo.png")
	badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	badge.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	badge.custom_minimum_size = Vector2(0, 96)
	col.add_child(badge)
	col.add_child(_heading("FIND A PLACE", font))
	var find := HBoxContainer.new()
	_search = LineEdit.new()
	_search.placeholder_text = "a name, or lat, lon"
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.text_submitted.connect(func(_t): _find())
	find.add_child(_search)
	var go := Button.new()
	go.text = "Find"
	go.pressed.connect(_find)
	find.add_child(go)
	col.add_child(find)
	col.add_child(_heading("THE SQUARE", font))
	_size_label = Label.new()
	col.add_child(_size_label)
	_size = HSlider.new()
	_size.min_value = 1.0
	_size.max_value = 6.0
	_size.step = 0.5
	_size.value = 3.0
	_size.value_changed.connect(_on_size)
	col.add_child(_size)
	_where = Label.new()
	_where.text = "click the map to choose its middle"
	_where.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_where)
	_title = LineEdit.new()
	_title.placeholder_text = "its name"
	col.add_child(_title)
	var bb := HBoxContainer.new()
	_build = Button.new()
	_build.text = "Build & fly"
	_build.disabled = true
	_build.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_build.pressed.connect(_start_build)
	bb.add_child(_build)
	_cancel = Button.new()
	_cancel.text = "Stop"
	_cancel.visible = false
	_cancel.pressed.connect(func(): if _builder: _builder.cancel())
	bb.add_child(_cancel)
	col.add_child(bb)
	_bar = ProgressBar.new()
	_bar.max_value = 1.0
	_bar.step = 0.001
	_bar.show_percentage = false
	_bar.visible = false
	col.add_child(_bar)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_status)
	col.add_child(_heading("BUILT HERE", font))
	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_selected.connect(_on_place_selected)
	_list.item_activated.connect(_on_place_activated)
	col.add_child(_list)
	var hint := Label.new()
	hint.text = "click: show it   double-click: fly there"
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.6, 0.65, 0.7))
	col.add_child(hint)
	var credit := Label.new()
	credit.text = "Relief and heights: Mapzen Terrain Tiles (AWS Open Data). Land cover: ESA WorldCover 2021 (CC BY 4.0). Search: © OpenStreetMap contributors (Nominatim)."
	credit.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	credit.add_theme_font_size_override("font_size", 11)
	credit.add_theme_color_override("font_color", Color(0.55, 0.6, 0.65))
	col.add_child(credit)
	_on_size(_size.value)
	refresh_places()


func _heading(t: String, font: Font) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", Color(0.65, 0.8, 0.95))
	return l


## The places built here, on the map and in the list.
func refresh_places() -> void:
	_places = Regions.list()
	_list.clear()
	var marks: Array = []
	for p in _places:
		_list.add_item("%s   %.3f, %.3f" % [p.title, p.lat, p.lon])
		marks.append({"lat": p.lat, "lon": p.lon, "size": p.size, "title": p.title})
	map.places = marks
	map.redraw()


func _on_size(v: float) -> void:
	_size_label.text = "%.1f km a side" % v
	map.square_m = v * 1000.0
	map.redraw()


func _on_picked(lat: float, lon: float) -> void:
	_where.text = "%.5f %s, %.5f %s" % [absf(lat), "N" if lat >= 0.0 else "S", absf(lon), "E" if lon >= 0.0 else "W"]
	if _title.text.strip_edges() == "" or _title.text == _found_title:
		_title.text = _found_title if _found_title != "" else "%.3f %s %.3f %s" % [absf(lat),
				"N" if lat >= 0.0 else "S", absf(lon), "E" if lon >= 0.0 else "W"]
	_build.disabled = _thread != null


func _on_place_selected(i: int) -> void:
	var p: Dictionary = _places[i]
	map.look_at_place(p.lat, p.lon, maxf(map.zoom, 11.0))


func _on_place_activated(i: int) -> void:
	fly.emit(String(_places[i].key))


# ------------------------------------------------------------------ finding

func _find() -> void:
	var q := _search.text.strip_edges()
	if q == "":
		return
	var m := RegEx.create_from_string("^\\s*(-?\\d+(?:\\.\\d+)?)\\s*[, ]\\s*(-?\\d+(?:\\.\\d+)?)\\s*$").search(q)
	if m != null:
		var lat := clampf(float(m.get_string(1)), -85.0, 85.0)
		var lon := wrapf(float(m.get_string(2)), -180.0, 180.0)
		_found_title = ""
		_choose(lat, lon)
		return
	_status.text = "looking for %s..." % q
	WorkerThreadPool.add_task(func():
		var r := GeoFetch.get_url(NOMINATIM % q.uri_encode(), -1, 0, [], true, 2)
		_found.call_deferred(q, r.body.get_string_from_utf8() if r.ok else ""), false, "nominatim")


func _found(q: String, text: String) -> void:
	var j: Variant = JSON.parse_string(text) if text != "" else null
	if not j is Array or (j as Array).is_empty():
		_status.text = "nothing found for %s" % q
		return
	var hit: Dictionary = (j as Array)[0]
	var name := String(hit.get("display_name", q))
	# (its name, its town and its region: the rest is postcodes and languages)
	var parts := name.split(",")
	_status.text = ", ".join(parts.slice(0, mini(3, parts.size())))
	_found_title = name.get_slice(",", 0).strip_edges().to_upper()
	_title.text = _found_title
	_choose(float(hit.get("lat", 0.0)), float(hit.get("lon", 0.0)))


func _choose(lat: float, lon: float) -> void:
	map.chosen = Vector2(lat, lon)
	map.look_at_place(lat, lon, 12.0)
	_on_picked(lat, lon)


# ------------------------------------------------------------------ building

func _start_build() -> void:
	if _thread != null or is_nan(map.chosen.x):
		return
	var title_text := _title.text.strip_edges()
	if title_text == "":
		title_text = "A PLACE"
	_name = Regions.name_for(title_text)
	_builder = RegionBuilder.new()
	_thread = Thread.new()
	var lat := map.chosen.x
	var lon := map.chosen.y
	var size_m := _size.value * 1000.0
	var b := _builder
	var name := _name
	var t := title_text.to_upper()
	_thread.start(func(): return b.build(name, t, lat, lon, size_m))
	_build.disabled = true
	_cancel.visible = true
	_bar.visible = true
	_bar.value = 0.0


func _process(_dt: float) -> void:
	if _thread == null:
		return
	var st := _builder.status()
	_bar.value = float(st.part)
	_status.text = "building: %s..." % st.stage
	if _thread.is_alive():
		return
	var dir: String = _thread.wait_to_finish()
	_thread = null
	_cancel.visible = false
	_bar.visible = false
	_build.disabled = is_nan(map.chosen.x)
	if dir == "":
		_status.text = "not built: %s" % _builder.error
		_builder = null
		return
	_status.text = "built %s (%s); flying there" % [_name, String(st.stage)]
	_builder = null
	refresh_places()
	fly.emit(Regions.PREFIX + _name)


func _exit_tree() -> void:
	if _thread != null:
		if _builder != null:
			_builder.cancel()
		_thread.wait_to_finish()
