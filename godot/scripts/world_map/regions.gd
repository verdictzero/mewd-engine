class_name Regions
extends RefCounted

## THE PLACES BUILT ON THIS MACHINE (the world map's: RegionBuilder, in
## user://regions/<name>/), as the viewer's places — each a spec like
## Islands.LIST's, drawn by the real-place template (OESCHINENSEE's scene)
## with its field pointed at the region's folder (`region`), so it has the
## same sky (at its own latitude and longitude), water, plants and picture.

const PREFIX := "built_"
## the scene every built place is drawn with
const TEMPLATE := "res://godot/island/earth/oeschinen/earth_oeschinen.tscn"


## Every built place, newest first: [spec...].
static func list() -> Array:
	var out: Array = []
	var d := DirAccess.open(RegionBuilder.ROOT)
	if d == null:
		return out
	for name in d.get_directories():
		var s := spec(PREFIX + name)
		if not s.is_empty():
			out.append(s)
	out.sort_custom(func(a, b): return String(a.made) > String(b.made))
	return out


## The place `key` names ("built_<name>"), or {} when there is none.
static func spec(key: String) -> Dictionary:
	if not key.begins_with(PREFIX):
		return {}
	var name := key.trim_prefix(PREFIX)
	var dir := RegionBuilder.dir_for(name)
	var j: Variant = JSON.parse_string(FileAccess.get_file_as_string(dir + "/region.json"))
	if not j is Dictionary:
		return {}
	var r: Dictionary = j
	return {
		"key": key, "title": String(r.get("title", name.to_upper())),
		"scene": TEMPLATE, "region": dir, "built": true,
		"lat": float(r.get("lat", 0.0)), "lon": float(r.get("lon", 0.0)),
		"size": float(r.get("size", 3000.0)), "made": String(r.get("made", "")),
		"blurb": "built here: %.4f, %.4f, a %.0f km square" % [float(r.get("lat", 0.0)),
				float(r.get("lon", 0.0)), float(r.get("size", 3000.0)) / 1000.0],
		"palette": false,
		# (from the middle, high enough to see the square, looking north)
		"start": Vector2.ZERO, "start_face": Vector2(0, -800), "start_high": 45.0,
		"sky": {"hour": 16.5, "day": 196, "weather": "fair"},
		"knee": 0.6,
		"grade": {"filmic": 1.0, "warmth": 0.2, "contrast": 0.14, "saturation": 1.05,
			"vibrance": 0.2, "split": 0.6, "lift": 0.04, "vignette": 0.32, "grain": 0.035},
	}


## A name for a new place from its title: lower case, letters, digits and _,
## not one already built.
static func name_for(title: String) -> String:
	var base := ""
	for ch in title.to_lower():
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
			base += ch
		elif base != "" and not base.ends_with("_"):
			base += "_"
	base = base.trim_suffix("_").substr(0, 40)
	if base == "" or not (base[0] >= "a" and base[0] <= "z"):
		base = "place_" + base
	var name := base
	var k := 2
	while DirAccess.dir_exists_absolute(RegionBuilder.dir_for(name)):
		name = "%s_%d" % [base, k]
		k += 1
	return name
