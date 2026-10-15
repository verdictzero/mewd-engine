class_name EarthField
extends IslandField

# A REAL PLACE ON EARTH, as an island: at the user's request, "take coordinates
# on earth and within defined boundaries (a square) render terrain faithfully
# using the chunk based terrain system ... using open source map data to define
# height, water level and vegetation / biomes".
#
# The field golf's islands are made of is a set of pure functions of world XZ,
# and the mesher, the bakes, the plant scatters and the ground the crowd walks on
# all ask it the same questions. This one answers them out of grids that
# `tools/earth_fetch.py` made from open data — the AWS Terrain Tiles for the
# height, ESA WorldCover for what is on the ground, OpenStreetMap for the water's
# edges, the roads and the forests' leaf type — instead of out of noise. So the
# island system needs nothing new to build it: the same chunks at the same LODs,
# baked the same way, with a cliff all round into the cloud.
#
# WHAT IS THE SAME. One hub, no satellites, `square_land` with no coast wobble:
# the island is exactly the square, its mask the fraction of the way in from the
# nearest edge. Every golf feature is off (no zones, bunkers, crater, pod, ruin).
#
# WHAT IS DIFFERENT, in the order the mesher meets it:
#
#   * `base_height` is the ground off `height.grid` (2 m, bilinear), less the
#     region's datum, so y = 0 is a metre under its lowest point — plus a little
#     relief finer than the source data has, more on rock than on turf, none at
#     the water's edge. There is no shore ramp: the land runs to the edge.
#   * `coast_y` (IslandField's hook for it) is that ground at the edge, so the
#     mesher's coast vertices sit on the real edge and the cliff's lip falls from
#     there: the square ends in a cut face, like a block lifted out of the map.
#   * `forest_at` and `sample()["forest"]` are WorldCover's tree cover.
#   * `sample()` carries four more keys the scatters and the game read when they
#     are there: "veg" (tree, conifer, bush, fern and grass densities), "water"
#     (how deep the water is over the ground, metres), "water_y" (its surface)
#     and "cover" (the twelve surface weights). Its "weights" are the twelve
#     folded into golf's four, for the code that reads those.
#   * `height_at` (the crowd's ground, `IslandGround`) is no ground where the
#     water is deeper than `wade_depth`: a lake is a coast to the crowd.
#
# The water itself is drawn by `SCRIPT_earth_dress.gd`, off `water.grid`, and
# the ground's twelve PBR layers by `SHADER_terrain_earth.gdshader`, off
# `cover.grid` — the vertex colours the mesher writes are not read.
#
# THE BAKES. A bake is keyed on the field's stored properties and the code that
# made it (`BakeStore.signature_for`). The grids are neither, so `data_digest`
# is: the digest `earth_fetch.py` writes into region.json, and this script's own,
# computed the first time anything asks and kept.
#
# THREADS. The mesher and the scatters clone the field per worker thread
# (`clone()` = duplicate + `prepare()`). The grids are read once per process
# into a static cache, under a mutex, and shared read-only between the clones.

## The twelve surface layers, in the order cover.grid holds them (and the
## terrain shader's texture arrays: tools/earth_pack.py `LAYERS`).
const L_GRASS := 0
const L_FOREST := 1
const L_ROCK := 2
const L_SCREE := 3
const L_SAND := 4
const L_SOIL := 5
const L_SNOW := 6
const L_MUD := 7
const L_PAVING := 8
const L_DRY := 9
const L_MOSS := 10
const L_BED := 11
const LAYERS := ["grass", "forest", "rock", "scree", "sand", "soil", "snow", "mud",
		"paving", "dry", "moss", "bed"]

## Water kinds in wkind.grid.
const W_NONE := 0
const W_SEA := 1
const W_LAKE := 2
const W_RIVER := 3

@export_group("Earth")
## The region's folder, as `tools/earth_fetch.py` wrote it.
@export_dir var region := "res://godot/island/earth/oeschinen"
## Relief finer than the data, in metres, on turf and earth.
@export var detail_height := 0.3
## More of it where the ground is rock or scree.
@export var detail_rock := 1.4
## The size of that relief's features, in metres.
@export var detail_scale := 14.0
## The deepest water the crowd and the player wade; deeper is no ground.
@export var wade_depth := 0.9

## What the bakes key on that the stored properties above cannot show: the
## region's data and this script. See the header.
@export_storage var data_digest := "":
	get:
		return _data_digest()


## One region's grids, read once per process and shared by every clone.
class Region extends RefCounted:
	var path := ""
	var ok := false
	var json := {}
	var size := 0.0
	var half := 0.0
	var datum := 0.0
	## height.grid: u16 samples, metres = offset + q * scale
	var hn := 0
	var hres := 2.0
	var hoff := 0.0
	var hscale := 1.0
	var hraw := PackedByteArray()
	## cover.grid: three RGBA planes stacked, cn x cn each
	var cn := 0
	var cres := 4.0
	var cover := PackedByteArray()
	## veg.grid: RGBA, tree / conifer / bush / grass
	var vn := 0
	var vres := 4.0
	var veg := PackedByteArray()
	## water.grid: the surface in metres above sea level, NaN none
	var wn := 0
	var wres := 4.0
	var water := PackedFloat32Array()
	var wkind := PackedByteArray()
	var digest := ""
	## The terrain shader's three control pictures (`control_textures`).
	var textures: Array = []


static var _regions := {}
static var _digests := {}
static var _lock := Mutex.new()

var _r: Region = null
var _detail: FastNoiseLite = null
var _hub_isl: Island = null


func prepare() -> void:
	super()
	_r = EarthField.region_for(region)
	_detail = FastNoiseLite.new()
	_detail.seed = world_seed ^ 0xEA27
	_detail.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_detail.frequency = 1.0 / maxf(detail_scale, 0.5)
	_detail.fractal_octaves = 3
	_hub_isl = island_in_cell(hub_cell())


## The region at `path`, read on first asking.
static func region_for(path: String) -> Region:
	_lock.lock()
	var r: Region = _regions.get(path)
	if r == null:
		r = _load(path)
		_regions[path] = r
	_lock.unlock()
	return r


## This field's region (reading it if no one has).
func data() -> Region:
	if _r == null:
		_r = EarthField.region_for(region)
	return _r


static func _load(path: String) -> Region:
	var r := Region.new()
	r.path = path
	var jtext := FileAccess.get_file_as_string(path.path_join("region.json"))
	var parsed: Variant = JSON.parse_string(jtext)
	if not parsed is Dictionary:
		push_error("EarthField: no region at %s (run tools/earth_fetch.py)" % path)
		return r
	var j: Dictionary = parsed
	r.json = j
	r.size = float(j.get("size", 0.0))
	r.half = r.size * 0.5
	r.datum = float(j.get("datum", 0.0))
	r.digest = String(j.get("digest", ""))
	var hj: Dictionary = j.get("height", {})
	var g := _grid(path.path_join(String(hj.get("file", "height.grid"))))
	r.hn = int(g.get("w", 0))
	r.hres = float(hj.get("res", 2.0))
	r.hoff = float(hj.get("offset", 0.0))
	r.hscale = float(hj.get("scale", 1.0))
	r.hraw = g.get("data", PackedByteArray())
	var cj: Dictionary = j.get("cover", {})
	g = _grid(path.path_join(String(cj.get("file", "cover.grid"))))
	r.cn = int(g.get("w", 0))
	r.cres = float(cj.get("res", 4.0))
	r.cover = g.get("data", PackedByteArray())
	var vj: Dictionary = j.get("veg", {})
	g = _grid(path.path_join(String(vj.get("file", "veg.grid"))))
	r.vn = int(g.get("w", 0))
	r.vres = float(vj.get("res", 4.0))
	r.veg = g.get("data", PackedByteArray())
	var wj: Dictionary = j.get("water", {})
	g = _grid(path.path_join(String(wj.get("file", "water.grid"))))
	r.wn = int(g.get("w", 0))
	r.wres = float(wj.get("res", 4.0))
	r.water = (g.get("data", PackedByteArray()) as PackedByteArray).to_float32_array()
	g = _grid(path.path_join(String(wj.get("kind", "wkind.grid"))))
	r.wkind = g.get("data", PackedByteArray())
	r.ok = r.hn > 1 and r.hraw.size() == r.hn * r.hn * 2 \
			and r.cover.size() == r.cn * r.cn * 12 and r.veg.size() == r.vn * r.vn * 4 \
			and r.water.size() == r.wn * r.wn and r.wkind.size() == r.wn * r.wn
	if not r.ok:
		push_error("EarthField: %s is incomplete; fetch it again" % path)
	return r


## One `MEWDGRD1` file: {w, h, type, ch, data} with the samples inflated.
static func _grid(file: String) -> Dictionary:
	var f := FileAccess.open(file, FileAccess.READ)
	if f == null:
		push_error("EarthField: cannot read %s" % file)
		return {}
	if f.get_buffer(8).get_string_from_ascii() != "MEWDGRD1":
		push_error("EarthField: %s is not a grid" % file)
		return {}
	var w := f.get_32()
	var h := f.get_32()
	var typ := f.get_8()
	var ch := f.get_8()
	f.get_16()
	var raw_len := f.get_32()
	var body := f.get_buffer(f.get_length() - f.get_position())
	return {"w": w, "h": h, "type": typ, "ch": ch,
			"data": body.decompress(raw_len, FileAccess.COMPRESSION_DEFLATE)}


func _data_digest() -> String:
	_lock.lock()
	var d: Variant = _digests.get(region)
	_lock.unlock()
	if d != null:
		return d
	var r := EarthField.region_for(region)
	var code := BakeStore.source_digest([(get_script() as Script).resource_path])
	var out := "%s|%s" % [r.digest, code]
	_lock.lock()
	_digests[region] = out
	_lock.unlock()
	return out


# ------------------------------------------------------------------ the ground

## The data's ground at a point, metres over the datum: the 2 m grid, bilinear,
## held at its edge past the square.
func ground(x: float, z: float) -> float:
	var r := _r if _r != null else data()
	if r.hn < 2:
		return 0.0
	var top := float(r.hn) - 1.0001
	var u := clampf((x + r.half) / r.hres, 0.0, top)
	var v := clampf((z + r.half) / r.hres, 0.0, top)
	var i := int(u)
	var j := int(v)
	var fu := u - float(i)
	var fv := v - float(j)
	var k := (j * r.hn + i) * 2
	var row := r.hn * 2
	var a := float(r.hraw.decode_u16(k))
	var b := float(r.hraw.decode_u16(k + 2))
	var c := float(r.hraw.decode_u16(k + row))
	var d := float(r.hraw.decode_u16(k + row + 2))
	var q := lerpf(lerpf(a, b, fu), lerpf(c, d, fu), fv)
	return r.hoff + q * r.hscale - r.datum


## The relief the data is too coarse to hold, metres: a few octaves of noise,
## stronger on rock and scree, gone at the water's edge (so a bank never dips
## under the water it holds back).
func relief(x: float, z: float) -> float:
	if _detail == null:
		return 0.0
	var amp := detail_height + detail_rock * (cover_at(x, z, L_ROCK)
			+ 0.6 * cover_at(x, z, L_SCREE))
	if not is_nan(water_y(x, z)):
		amp *= 0.15
	return _detail.get_noise_2d(x, z) * amp


func base_height(x: float, z: float, _mask: float, owner: Island,
		_zone_flat := 0.0, _zone_lift := 0.0) -> float:
	if owner == null:
		return 0.0
	return owner.base_y + ground(x, z) + relief(x, z)


func coast_y(isl: Island, x: float, z: float) -> float:
	return base_height(x, z, 0.0, isl)


func forest_at(x: float, z: float, _mask: float, _slope: float,
		_zone_flat := 0.0) -> float:
	return veg_at(x, z).x


## The water's surface over a point, metres over the datum, or NAN where there
## is none (the nearest 4 m sample: the grid runs a few metres past every shore).
func water_y(x: float, z: float) -> float:
	var r := _r if _r != null else data()
	if r.wn < 2:
		return NAN
	var i := clampi(int(round((x + r.half) / r.wres)), 0, r.wn - 1)
	var j := clampi(int(round((z + r.half) / r.wres)), 0, r.wn - 1)
	var w := r.water[j * r.wn + i]
	return NAN if is_nan(w) else w - r.datum


## Which water is over a point: W_NONE, W_SEA, W_LAKE or W_RIVER.
func water_kind(x: float, z: float) -> int:
	var r := _r if _r != null else data()
	if r.wn < 2:
		return W_NONE
	var i := clampi(int(round((x + r.half) / r.wres)), 0, r.wn - 1)
	var j := clampi(int(round((z + r.half) / r.wres)), 0, r.wn - 1)
	return r.wkind[j * r.wn + i]


## One surface layer's weight at a point, 0..1, bilinear on the 4 m grid.
func cover_at(x: float, z: float, layer: int) -> float:
	var r := _r if _r != null else data()
	if r.cn < 2:
		return 0.0
	var top := float(r.cn) - 1.0001
	var u := clampf((x + r.half) / r.cres, 0.0, top)
	var v := clampf((z + r.half) / r.cres, 0.0, top)
	var i := int(u)
	var j := int(v)
	var fu := u - float(i)
	var fv := v - float(j)
	var base := (layer >> 2) * r.cn * r.cn * 4 + (layer & 3)
	var k := base + (j * r.cn + i) * 4
	var row := r.cn * 4
	var a := float(r.cover[k])
	var b := float(r.cover[k + 4])
	var c := float(r.cover[k + row])
	var d := float(r.cover[k + row + 4])
	return lerpf(lerpf(a, b, fu), lerpf(c, d, fu), fv) / 255.0


## All twelve, in `LAYERS` order.
func cover(x: float, z: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(12)
	for l in range(12):
		out[l] = cover_at(x, z, l)
	return out


## The plants at a point: (trees, their conifer share, bushes, grass), 0..1.
func veg_at(x: float, z: float) -> Vector4:
	var r := _r if _r != null else data()
	if r.vn < 2:
		return Vector4.ZERO
	var top := float(r.vn) - 1.0001
	var u := clampf((x + r.half) / r.vres, 0.0, top)
	var v := clampf((z + r.half) / r.vres, 0.0, top)
	var i := int(u)
	var j := int(v)
	var fu := u - float(i)
	var fv := v - float(j)
	var k := (j * r.vn + i) * 4
	var row := r.vn * 4
	var out := Vector4.ZERO
	for c in range(4):
		var a := float(r.veg[k + c])
		var b := float(r.veg[k + 4 + c])
		var e := float(r.veg[k + row + c])
		var d := float(r.veg[k + row + 4 + c])
		out[c] = lerpf(lerpf(a, b, fu), lerpf(e, d, fu), fv) / 255.0
	return out


# ------------------------------------------------------------------ gameplay

func sample(x: float, z: float) -> Dictionary:
	var s := super.sample(x, z)
	if not s.get("on_land", false):
		return s
	var cv := cover(x, z)
	var vg := veg_at(x, z)
	var wy := water_y(x, z)
	var h: float = s["height"]
	var depth := 0.0 if is_nan(wy) else maxf(wy - h, 0.0)
	# golf's four, for the code that reads those: turf, earth, stone, sand
	var turf := cv[L_GRASS] + 0.5 * cv[L_FOREST] + cv[L_MOSS] + 0.7 * cv[L_DRY] + 0.5 * cv[L_MUD]
	var earth := cv[L_SOIL] + 0.5 * cv[L_FOREST] + 0.5 * cv[L_MUD] + cv[L_PAVING] \
			+ 0.3 * cv[L_DRY] + cv[L_BED]
	var stone := cv[L_ROCK] + cv[L_SCREE] + cv[L_SNOW]
	var sand := cv[L_SAND]
	var sum := maxf(turf + earth + stone + sand, 1e-5)
	var w := Color(turf / sum, earth / sum, stone / sum, sand / sum)
	var names := ["grass", "soil", "rock", "sand"]
	var vals := [w.r, w.g, w.b, w.a]
	var top := 0
	for i in range(1, 4):
		if vals[i] > vals[top]:
			top = i
	var dry := 1.0 if depth <= 0.05 else 0.0
	s["weights"] = w
	s["surface"] = names[top]
	s["forest"] = vg.x * dry
	s["veg"] = {
		"tree": vg.x * dry,
		"conifer": vg.y,
		"bush": vg.z * dry,
		# ferns and low growth under the trees, and along the wet edges
		"fern": clampf(vg.x * 0.75 + cv[L_MUD] * 0.4, 0.0, 1.0) * dry,
		"grass": vg.w * dry,
	}
	s["water"] = depth
	s["water_y"] = wy
	s["cover"] = cv
	return s


func height_at(x: float, z: float, fallback := -1e9) -> float:
	if not _ready:
		prepare()
	var isl := _hub_isl
	if isl == null or mask_for(isl, x, z) <= 0.0:
		return fallback
	var h := base_height(x, z, 1.0, isl)
	var wy := water_y(x, z)
	if not is_nan(wy) and wy - h > wade_depth:
		return fallback
	return h


# ------------------------------------------------------------------ drawing

## The terrain shader's three control pictures, four layers each, made once
## (on the main thread: textures are the renderer's).
func control_textures() -> Array:
	var r := data()
	if not r.textures.is_empty() or r.cn < 2:
		return r.textures
	var plane := r.cn * r.cn * 4
	for k in range(3):
		var img := Image.create_from_data(r.cn, r.cn, false, Image.FORMAT_RGBA8,
				r.cover.slice(k * plane, (k + 1) * plane))
		r.textures.append(ImageTexture.create_from_image(img))
	return r.textures


## The square's half side, metres.
func half_size() -> float:
	return data().half
