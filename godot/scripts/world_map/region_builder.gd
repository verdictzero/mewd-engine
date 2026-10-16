class_name RegionBuilder
extends RefCounted

## A REAL PLACE, MADE INSIDE THE APP (at the user's request: "a planet-wide
## selector (2D) where you select the area you want to render in 3D, and then
## it renders it", "keep it inside the app, linux only"): the square round a
## point anywhere on Earth fetched and worked into the grids EarthField reads
## — tools/earth_fetch.py's build, in GDScript, without OpenStreetMap for now:
##
##   HEIGHT   the AWS Terrain Tiles (Terrarium PNGs, zoom 14), bicubic onto a
##            2 m grid and blurred against the 30 m checker under them
##   COVER    ESA WorldCover 10 m (its cloud-optimised GeoTIFFs, by range
##            request: Cog), sampled softly at points pushed about a few
##            metres, so the classes' edges wander instead of stepping
##   WATER    WorldCover's water class (and, where it has no tile at all,
##            the open sea under sea level): the bodies found and told apart
##            — the sea at 0, a lake at the level of its lowest shore, a
##            river falling with its banks — their beds carved, their banks
##            held up out of them
##   LAYERS   the twelve ground layers off the cover, the slope (rock where it
##            is steep, scree under it), the shores and the beds
##   PLANTS   trees, the conifers' share (by altitude and latitude), bushes
##            and grass
##
## into user://regions/<name>/ — height.grid, water.grid, wkind.grid,
## cover.grid, veg.grid and region.json, as the Python tool writes them — on
## whatever thread calls `build` (the world map runs it on its own, and
## reads `status()` for its bar).
##
## FASTER THAN A LINE-FOR-LINE PORT WOULD BE, and as near as matters: the
## layers and the plants are worked out at the 4 m they are stored at (the
## water and the carving at 2 m); a river's surface is its nearest bank's
## height smoothed along it rather than relaxed across it; the noise is
## Godot's own.

const LAYERS := ["grass", "forest", "rock", "scree", "sand", "soil",
		"snow", "mud", "paving", "dry", "moss", "bed"]
enum { L_GRASS, L_FOREST, L_ROCK, L_SCREE, L_SAND, L_SOIL, L_SNOW, L_MUD,
		L_PAVING, L_DRY, L_MOSS, L_BED }
## ESA WorldCover's classes, as surface layers (weights summing to one)
const WC_LAYERS := {
	10: {L_FOREST: 1.0}, 20: {L_DRY: 0.7, L_GRASS: 0.3}, 30: {L_GRASS: 1.0},
	40: {L_SOIL: 0.55, L_GRASS: 0.45}, 50: {L_PAVING: 0.6, L_GRASS: 0.4},
	60: {L_SCREE: 0.75, L_ROCK: 0.25}, 70: {L_SNOW: 1.0}, 80: {L_BED: 1.0},
	90: {L_MUD: 0.5, L_GRASS: 0.5}, 95: {L_MUD: 0.6, L_FOREST: 0.4},
	100: {L_MOSS: 0.7, L_SCREE: 0.3}, 0: {L_GRASS: 1.0},
}
const ROOT := "user://regions"
const RES := 2.0
const ZOOM := 14
## metres of blur on the DEM against its 30 m checker
const SMOOTH := 8.0

var error := ""
var _lock := Mutex.new()
var _stage := ""
var _part := 0.0
var _cancel := false

# the square
var _lat := 0.0
var _lon := 0.0
var _size := 0.0
var _half := 0.0
var _n := 0
var _n4 := 0
var _mlat := 1.0
var _mlon := 1.0


## Where it is, as words, and how far through (0..1).
func status() -> Dictionary:
	_lock.lock()
	var d := {"stage": _stage, "part": _part, "error": error}
	_lock.unlock()
	return d


func cancel() -> void:
	_cancel = true


func _say(stage: String, part: float) -> void:
	_lock.lock()
	_stage = stage
	_part = part
	_lock.unlock()


## A region's folder for this name.
static func dir_for(name: String) -> String:
	return "%s/%s" % [ROOT, name]


## Build the square `size` metres a side round (lat, lon) as `name`. Returns
## its folder, or "" (and `error` says why).
func build(name: String, title: String, lat: float, lon: float, size: float) -> String:
	var t0 := Time.get_ticks_msec()
	_lat = lat
	_lon = lon
	_size = float(int(clampf(size, 256.0, 6000.0) / 4.0) * 4)
	_half = _size * 0.5
	_n = int(roundf(_size / RES)) + 1
	_n4 = (_n - 1) / 2 + 1
	var mpd := metres_per_degree(lat)
	_mlat = mpd.x
	_mlon = mpd.y
	_say("the ground's height", 0.02)
	var dem := _terrarium()
	if dem.is_empty():
		return ""
	if _cancel:
		return _cancelled()
	_say("smoothing the ground", 0.22)
	dem = _blur(dem, _n, _n, SMOOTH / 2.0)
	_say("what covers the ground", 0.3)
	var cover := _worldcover(dem)
	if cover.is_empty():
		return ""
	if _cancel:
		return _cancelled()
	_say("the water", 0.5)
	var w := _water(dem, cover)
	if _cancel:
		return _cancelled()
	_say("the ground's layers and its plants", 0.72)
	var lv := _layers_and_plants(dem, cover, w)
	if _cancel:
		return _cancelled()
	_say("writing the place", 0.9)
	var dir := _write(name, title, w, lv)
	if dir != "":
		_say("done in %.0f s" % ((Time.get_ticks_msec() - t0) / 1000.0), 1.0)
	return dir


func _cancelled() -> String:
	error = "cancelled"
	return ""


## WGS84 metres per degree of latitude (x) and of longitude (y) at `lat`.
static func metres_per_degree(lat: float) -> Vector2:
	var p := deg_to_rad(lat)
	return Vector2(111132.92 - 559.82 * cos(2 * p) + 1.175 * cos(4 * p) - 0.0023 * cos(6 * p),
			111412.84 * cos(p) - 93.5 * cos(3 * p) + 0.118 * cos(5 * p))


# --------------------------------------------------------------- the DEM

func _row_lat(j: int, step := RES) -> float:
	return _lat - (-_half + j * step) / _mlat


func _col_lon(i: int, step := RES) -> float:
	return _lon + (-_half + i * step) / _mlon


static func merc_y(lat: float, world_px: float) -> float:
	var p := deg_to_rad(clampf(lat, -85.05, 85.05))
	return (1.0 - log(tan(p) + 1.0 / cos(p)) / PI) / 2.0 * world_px


func _terrarium() -> PackedFloat32Array:
	var n := _n
	var world := float(1 << ZOOM) * 256.0
	var px := PackedFloat32Array()
	px.resize(n)
	var py := PackedFloat32Array()
	py.resize(n)
	for i in range(n):
		px[i] = (_col_lon(i) + 180.0) / 360.0 * world
		py[i] = merc_y(_row_lat(i), world)
	var tx0 := int(floor((px[0] - 4.0) / 256.0))
	var tx1 := int(floor((px[n - 1] + 4.0) / 256.0))
	var ty0 := int(floor((py[0] - 4.0) / 256.0))
	var ty1 := int(floor((py[n - 1] + 4.0) / 256.0))
	var tw := tx1 - tx0 + 1
	var th := ty1 - ty0 + 1
	var mw := tw * 256
	var mh := th * 256
	var tiles: Array = []
	tiles.resize(tw * th)
	var nz := 1 << ZOOM
	var fetch := func(k: int) -> void:
		var tx := tx0 + k % tw
		var ty := ty0 + k / tw
		var r := GeoFetch.get_url("https://s3.amazonaws.com/elevation-tiles-prod/terrarium/%d/%d/%d.png"
				% [ZOOM, posmod(tx, nz), ty])
		var img := Image.new()
		if r.ok and img.load_png_from_buffer(r.body) == OK:
			img.convert(Image.FORMAT_RGB8)
			tiles[k] = img.get_data()
	var task := WorkerThreadPool.add_group_task(fetch, tw * th, mini(tw * th, 8), true, "terrarium")
	WorkerThreadPool.wait_for_group_task_completion(task)
	var mosaic := PackedFloat32Array()
	mosaic.resize(mw * mh)
	var got := 0
	for k in range(tw * th):
		var d: PackedByteArray = tiles[k] if tiles[k] != null else PackedByteArray()
		if d.size() < 256 * 256 * 3:
			continue
		got += 1
		var ox := (k % tw) * 256
		var oy := (k / tw) * 256
		for y in range(256):
			var row := (oy + y) * mw + ox
			var src := y * 256 * 3
			for x in range(256):
				var s := src + x * 3
				mosaic[row + x] = d[s] * 256.0 + d[s + 1] + d[s + 2] / 256.0 - 32768.0
	if got == 0:
		error = "no height data could be fetched (no network?)"
		return PackedFloat32Array()
	_say("the ground's height", 0.15)
	# bicubic, separable: the square's columns depend on the longitude alone
	# and its rows on the latitude alone
	var u0 := tx0 * 256.0 + 0.5
	var v0 := ty0 * 256.0 + 0.5
	var iu := PackedInt32Array()
	iu.resize(n)
	var wu := PackedFloat32Array()
	wu.resize(n * 4)
	var iv := PackedInt32Array()
	iv.resize(n)
	var wv := PackedFloat32Array()
	wv.resize(n * 4)
	for i in range(n):
		var u := clampf(px[i] - u0, 1.0, mw - 3.0001)
		var v := clampf(py[i] - v0, 1.0, mh - 3.0001)
		iu[i] = int(u)
		iv[i] = int(v)
		_cr_weights(u - iu[i], wu, i * 4)
		_cr_weights(v - iv[i], wv, i * 4)
	var r0 := iv[0] - 1
	var r1 := iv[n - 1] + 3
	var rows := r1 - r0
	var tmp := PackedFloat32Array()
	tmp.resize(rows * n)
	for r in range(rows):
		var mrow := (r0 + r) * mw
		var orow := r * n
		for i in range(n):
			var b := mrow + iu[i] - 1
			var k := i * 4
			tmp[orow + i] = wu[k] * mosaic[b] + wu[k + 1] * mosaic[b + 1] \
					+ wu[k + 2] * mosaic[b + 2] + wu[k + 3] * mosaic[b + 3]
	var out := PackedFloat32Array()
	out.resize(n * n)
	for j in range(n):
		var k := j * 4
		var b := (iv[j] - 1 - r0) * n
		var a0 := wv[k]
		var a1 := wv[k + 1]
		var a2 := wv[k + 2]
		var a3 := wv[k + 3]
		var o := j * n
		for i in range(n):
			out[o + i] = a0 * tmp[b + i] + a1 * tmp[b + n + i] + a2 * tmp[b + 2 * n + i] + a3 * tmp[b + 3 * n + i]
	return out


static func _cr_weights(t: float, w: PackedFloat32Array, o: int) -> void:
	var t2 := t * t
	var t3 := t2 * t
	w[o] = (-t3 + 2.0 * t2 - t) * 0.5
	w[o + 1] = (3.0 * t3 - 5.0 * t2 + 2.0) * 0.5
	w[o + 2] = (-3.0 * t3 + 4.0 * t2 + t) * 0.5
	w[o + 3] = (t3 - t2) * 0.5


# ------------------------------------------------------------ the filters

## A mean over a (2r+1)-square, edges clamped: running sums along the rows,
## then down the columns.
static func _box(a: PackedFloat32Array, w: int, h: int, r: int) -> PackedFloat32Array:
	if r <= 0:
		return a
	var k := 1.0 / (2 * r + 1)
	var mid := PackedFloat32Array()
	mid.resize(w * h)
	for y in range(h):
		var o := y * w
		var s := 0.0
		for d in range(-r, r + 1):
			s += a[o + clampi(d, 0, w - 1)]
		for x in range(w):
			mid[o + x] = s * k
			s += a[o + mini(x + r + 1, w - 1)] - a[o + maxi(x - r, 0)]
	var out := PackedFloat32Array()
	out.resize(w * h)
	var acc := PackedFloat32Array()
	acc.resize(w)
	for d in range(-r, r + 1):
		var o := clampi(d, 0, h - 1) * w
		for x in range(w):
			acc[x] += mid[o + x]
	for y in range(h):
		var o := y * w
		var add := mini(y + r + 1, h - 1) * w
		var sub := maxi(y - r, 0) * w
		for x in range(w):
			out[o + x] = acc[x] * k
			acc[x] += mid[add + x] - mid[sub + x]
	return out


## About a Gaussian of `sigma` samples: three box passes.
static func _blur(a: PackedFloat32Array, w: int, h: int, sigma: float) -> PackedFloat32Array:
	if sigma <= 0.3:
		return a
	var r := maxi(int(roundf(sqrt(12.0 * sigma * sigma / 3.0 + 1.0) / 2.0 - 0.5)), 1)
	var out := a
	for i in range(3):
		out = _box(out, w, h, r)
	return out


## Noise in about [-1, 1] over w x h, features `cell` samples across.
static func _noise(w: int, h: int, cell: float, seed: int, octaves: int) -> PackedFloat32Array:
	var nz := FastNoiseLite.new()
	nz.noise_type = FastNoiseLite.TYPE_VALUE_CUBIC
	nz.seed = seed
	nz.frequency = 1.0 / maxf(cell, 1.0)
	nz.fractal_type = FastNoiseLite.FRACTAL_FBM if octaves > 1 else FastNoiseLite.FRACTAL_NONE
	nz.fractal_octaves = octaves
	var img := nz.get_image(w, h, false, false, false)
	img.convert(Image.FORMAT_L8)
	var d := img.get_data()
	var out := PackedFloat32Array()
	out.resize(w * h)
	for i in range(w * h):
		out[i] = d[i] / 127.5 - 1.0
	return out


static func _smooth(a: float, b: float, x: float) -> float:
	var t := clampf((x - a) / maxf(b - a, 1e-9), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


# ------------------------------------------------------------ the cover

## WorldCover at the 4 m grid: {"slots": [class...], "f": flat array of each
## slot's share at every sample (slot * n4^2 + index)}, its pixels sampled
## bilinearly as 0/1 maps at points pushed about a few metres.
func _worldcover(dem: PackedFloat32Array) -> Dictionary:
	var n4 := _n4
	var nn := n4 * n4
	var wx := _noise(n4, n4, 6.0, 11, 3)
	var wz := _noise(n4, n4, 6.0, 12, 3)
	# the class at the four corners of each sample, and the weights
	var cls := PackedInt32Array()
	cls.resize(nn * 4)
	var wts := PackedFloat32Array()
	wts.resize(nn * 4)
	var covered := PackedByteArray()
	covered.resize(nn)
	var lat_lo := _row_lat(n4 - 1, RES * 2) - 0.01
	var lat_hi := _row_lat(0, RES * 2) + 0.01
	var lon_lo := _col_lon(0, RES * 2) - 0.01
	var lon_hi := _col_lon(n4 - 1, RES * 2) + 0.01
	var la0 := int(floor(lat_lo / 3.0)) * 3
	var lo0 := int(floor(lon_lo / 3.0)) * 3
	var la := la0
	while la <= int(floor(lat_hi / 3.0)) * 3:
		var lo := lo0
		while lo <= int(floor(lon_hi / 3.0)) * 3:
			var name := "ESA_WorldCover_10m_2021_v200_%s%s_Map" % [_hemi(la, "N", "S", 2), _hemi(lo, "E", "W", 3)]
			var cog := Cog.new("https://esa-worldcover.s3.eu-central-1.amazonaws.com/v200/2021/map/%s.tif" % name)
			if cog.ok:
				_sample_cover(cog, la, lo, wx, wz, cls, wts, covered)
			lo += 3
		la += 3
	# where no tile reaches (the open sea): water under sea level, else grass
	var present := {}
	for s in range(nn):
		if covered[s] == 0:
			var c := 80 if dem[(2 * (s / n4)) * _n + 2 * (s % n4)] < 0.5 else 0
			for k in range(4):
				cls[s * 4 + k] = c
				wts[s * 4 + k] = 0.25
	for i in range(nn * 4):
		present[cls[i]] = true
	var slots: Array = present.keys()
	slots.sort()
	var slot_of := PackedInt32Array()
	slot_of.resize(256)
	for k in range(slots.size()):
		slot_of[int(slots[k])] = k
	var f := PackedFloat32Array()
	f.resize(slots.size() * nn)
	for s in range(nn):
		for k in range(4):
			var q := s * 4 + k
			f[slot_of[cls[q]] * nn + s] += wts[q]
	return {"slots": slots, "f": f}


func _sample_cover(cog: Cog, la: int, lo: int, wx: PackedFloat32Array, wz: PackedFloat32Array,
		cls: PackedInt32Array, wts: PackedFloat32Array, covered: PackedByteArray) -> void:
	var n4 := _n4
	var step := RES * 2.0
	var pad := 30.0
	var u_lo := (_col_lon(0, step) - pad / _mlon - cog.x0) / cog.sx
	var u_hi := (_col_lon(n4 - 1, step) + pad / _mlon - cog.x0) / cog.sx
	var v_lo := (cog.y0 - (_row_lat(0, step) + pad / _mlat)) / cog.sy
	var v_hi := (cog.y0 - (_row_lat(n4 - 1, step) - pad / _mlat)) / cog.sy
	var win := cog.window(int(floor(u_lo)) - 1, int(floor(v_lo)) - 1, int(ceil(u_hi)) + 2, int(ceil(v_hi)) + 2)
	var ww: int = win.w
	var wh: int = win.h
	if ww < 2 or wh < 2:
		return
	var data: PackedFloat32Array = win.data
	var c0: int = win.c0
	var r0: int = win.r0
	for j in range(n4):
		for i in range(n4):
			var s := j * n4 + i
			var lat := _lat - (-_half + j * step + wz[s] * 7.0) / _mlat
			var lon := _lon + (-_half + i * step + wx[s] * 7.0) / _mlon
			if lat < la or lat >= la + 3 or lon < lo or lon >= lo + 3:
				continue
			var u := clampf((lon - cog.x0) / cog.sx - c0, 0.0, ww - 1.001)
			var v := clampf((cog.y0 - lat) / cog.sy - r0, 0.0, wh - 1.001)
			var iu := int(u)
			var iv := int(v)
			var fu := u - iu
			var fv := v - iv
			var b := iv * ww + iu
			var q := s * 4
			cls[q] = int(data[b])
			cls[q + 1] = int(data[b + 1])
			cls[q + 2] = int(data[b + ww])
			cls[q + 3] = int(data[b + ww + 1])
			wts[q] = (1.0 - fu) * (1.0 - fv)
			wts[q + 1] = fu * (1.0 - fv)
			wts[q + 2] = (1.0 - fu) * fv
			wts[q + 3] = fu * fv
			covered[s] = 1


static func _hemi(v: int, pos: String, neg: String, width: int) -> String:
	return ("%s%0" + str(width) + "d") % [pos if v >= 0 else neg, absi(v)]


## The share of these classes at every 4 m sample.
func _wcf(cover: Dictionary, classes: Array) -> PackedFloat32Array:
	var nn := _n4 * _n4
	var out := PackedFloat32Array()
	out.resize(nn)
	var slots: Array = cover.slots
	var f: PackedFloat32Array = cover.f
	for c in classes:
		var k := slots.find(c)
		if k < 0:
			continue
		var o := k * nn
		for s in range(nn):
			out[s] += f[o + s]
	return out


# ------------------------------------------------------------ the water

## Distance from every cell to the nearest set cell of `feature`, times
## `step`: a (1, sqrt 2) chamfer in two sweeps.
static func _chamfer(feature: PackedByteArray, w: int, h: int, step: float) -> PackedFloat32Array:
	var big := 1e9
	var d := PackedFloat32Array()
	d.resize(w * h)
	for i in range(w * h):
		d[i] = 0.0 if feature[i] != 0 else big
	var dg := sqrt(2.0)
	for y in range(h):
		var o := y * w
		for x in range(w):
			var i := o + x
			var v := d[i]
			if v == 0.0:
				continue
			if x > 0:
				v = minf(v, d[i - 1] + 1.0)
			if y > 0:
				v = minf(v, d[i - w] + 1.0)
				if x > 0:
					v = minf(v, d[i - w - 1] + dg)
				if x < w - 1:
					v = minf(v, d[i - w + 1] + dg)
			d[i] = v
	for y in range(h - 1, -1, -1):
		var o := y * w
		for x in range(w - 1, -1, -1):
			var i := o + x
			var v := d[i]
			if v == 0.0:
				continue
			if x < w - 1:
				v = minf(v, d[i + 1] + 1.0)
			if y < h - 1:
				v = minf(v, d[i + w] + 1.0)
				if x < w - 1:
					v = minf(v, d[i + w + 1] + dg)
				if x > 0:
					v = minf(v, d[i + w - 1] + dg)
			d[i] = v
	for i in range(w * h):
		d[i] *= step
	return d


## 4-connected components of `mask`: labels counting from 1 (0 none), and the
## count, by a union-find over the cells.
static func _label(mask: PackedByteArray, w: int, h: int) -> Dictionary:
	var lab := PackedInt32Array()
	lab.resize(w * h)
	var parent := PackedInt32Array([0])
	for y in range(h):
		for x in range(w):
			var i := y * w + x
			if mask[i] == 0:
				continue
			var a := lab[i - 1] if x > 0 else 0
			var b := lab[i - w] if y > 0 else 0
			if a == 0 and b == 0:
				parent.append(parent.size())
				lab[i] = parent.size() - 1
			elif a == 0 or b == 0 or a == b:
				lab[i] = maxi(a, b)
			else:
				# union the two roots, the smaller kept
				var ra := a
				while parent[ra] != ra:
					ra = parent[ra]
				var rb := b
				while parent[rb] != rb:
					rb = parent[rb]
				var lo := mini(ra, rb)
				parent[ra] = lo
				parent[rb] = lo
				parent[a] = lo
				parent[b] = lo
				lab[i] = lo
	var compact := PackedInt32Array()
	compact.resize(parent.size())
	var count := 0
	for k in range(1, parent.size()):
		var r := k
		while parent[r] != r:
			r = parent[r]
		parent[k] = r
		if r == k:
			count += 1
			compact[k] = count
	for i in range(w * h):
		if lab[i] != 0:
			lab[i] = compact[parent[lab[i]]]
	return {"lab": lab, "count": count}


## Labels grown `steps` cells into the cells that have none (4-connected).
static func _grow(lab: PackedInt32Array, w: int, h: int, steps: int) -> PackedInt32Array:
	var cur := lab
	for s in range(steps):
		var nxt := cur.duplicate()
		for y in range(h):
			for x in range(w):
				var i := y * w + x
				if cur[i] != 0:
					continue
				var v := 0
				if y > 0 and cur[i - w] != 0:
					v = cur[i - w]
				elif y < h - 1 and cur[i + w] != 0:
					v = cur[i + w]
				elif x > 0 and cur[i - 1] != 0:
					v = cur[i - 1]
				elif x < w - 1 and cur[i + 1] != 0:
					v = cur[i + 1]
				nxt[i] = v
		cur = nxt
	return cur


func _percentile(vals: PackedFloat32Array, p: float) -> float:
	if vals.is_empty():
		return 0.0
	var s := vals.duplicate()
	s.sort()
	var k := clampf(p / 100.0 * (s.size() - 1), 0.0, s.size() - 1)
	var i := int(k)
	return lerpf(s[i], s[mini(i + 1, s.size() - 1)], k - i)


## The water: which cells, at what surface, of which kind; the ground with
## the beds carved and the banks held up. Every array at 2 m.
func _water(dem: PackedFloat32Array, cover: Dictionary) -> Dictionary:
	var n := _n
	var nn := n * n
	var n4 := _n4
	# WorldCover's water share, from 4 m back up to 2 m
	var w4 := _wcf(cover, [80])
	var wmask := PackedByteArray()
	wmask.resize(nn)
	for j in range(n):
		var j0 := j / 2
		var j1 := mini((j + 1) / 2, n4 - 1)
		for i in range(n):
			var i0 := i / 2
			var i1 := mini((i + 1) / 2, n4 - 1)
			var v := (w4[j0 * n4 + i0] + w4[j0 * n4 + i1] + w4[j1 * n4 + i0] + w4[j1 * n4 + i1]) * 0.25
			wmask[j * n + i] = 1 if v >= 0.5 else 0
	var labd := _label(wmask, n, n)
	var lab: PackedInt32Array = labd.lab
	var count: int = labd.count
	var land := PackedByteArray()
	land.resize(nn)
	for i in range(nn):
		land[i] = 1 - wmask[i]
	var d_in := _chamfer(land, n, n, RES)
	var d_out := _chamfer(wmask, n, n, RES)
	var ring_lab := _grow(lab, n, n, 3)
	# each body's cells, and the ring of land round it, gathered body by body
	var cnt := PackedInt32Array()
	cnt.resize(count + 1)
	var rcnt := PackedInt32Array()
	rcnt.resize(count + 1)
	var dmax := PackedFloat32Array()
	dmax.resize(count + 1)
	var edge := PackedByteArray()
	edge.resize(count + 1)
	for i in range(nn):
		var b := lab[i]
		if b != 0:
			cnt[b] += 1
			dmax[b] = maxf(dmax[b], d_in[i])
			var x := i % n
			var y := i / n
			if x == 0 or y == 0 or x == n - 1 or y == n - 1:
				edge[b] = 1
		elif ring_lab[i] != 0:
			rcnt[ring_lab[i]] += 1
	var off := PackedInt32Array()
	off.resize(count + 2)
	var roff := PackedInt32Array()
	roff.resize(count + 2)
	for b in range(1, count + 1):
		off[b + 1] = off[b] + cnt[b]
		roff[b + 1] = roff[b] + rcnt[b]
	var inside := PackedFloat32Array()
	inside.resize(off[count + 1])
	var ringh := PackedFloat32Array()
	ringh.resize(roff[count + 1])
	var cur := off.duplicate()
	var rcur := roff.duplicate()
	for i in range(nn):
		var b := lab[i]
		if b != 0:
			inside[cur[b]] = dem[i]
			cur[b] += 1
		elif ring_lab[i] != 0:
			var rb := ring_lab[i]
			ringh[rcur[rb]] = dem[i]
			rcur[rb] += 1
	# what each body is, and its level
	var kind_of := PackedByteArray()
	kind_of.resize(count + 1)
	var level_of := PackedFloat32Array()
	level_of.resize(count + 1)
	var bodies: Array = []
	var climb := PackedFloat32Array()
	climb.resize(nn)
	for b in range(1, count + 1):
		var area := cnt[b] * RES * RES
		if area < 60.0:
			continue
		var rh := ringh.slice(roff[b], roff[b + 1])
		var ins := inside.slice(off[b], off[b + 1])
		if rh.is_empty():
			rh = ins
		var p15 := _percentile(rh, 15.0)
		var p5 := _percentile(rh, 5.0)
		var elong := area / (PI * pow(maxf(dmax[b], 1.0), 2.0))
		var k := 2
		var level := 0.0
		if p15 < 2.5 and (edge[b] == 1 or area > 2e5) and p5 < 6.0:
			k = 1
			level = 0.0
		elif elong > 6.0 and dmax[b] < 60.0:
			k = 3
		else:
			var med := _percentile(ins, 50.0)
			level = med if absf(med - p15) < 2.0 else p15
			level -= 0.1
			var high := 0
			for v in ins:
				if v > level + 2.5:
					high += 1
			if float(high) / ins.size() > 0.3:
				level = med - 0.3
		kind_of[b] = k
		level_of[b] = level
	# cells of a lake standing metres over its level are its climbing arm:
	# out of the water, a stream's channel
	for i in range(nn):
		var b := lab[i]
		if b == 0:
			continue
		if kind_of[b] == 0:
			wmask[i] = 0
			lab[i] = 0
		elif kind_of[b] == 2 and dem[i] > level_of[b] + 2.5:
			climb[i] = 1.0
			wmask[i] = 0
			lab[i] = 0
	# a river's surface: its nearest bank's height, smoothed along it
	var surface := PackedFloat32Array()
	surface.resize(nn)
	surface.fill(NAN)
	var kind := PackedByteArray()
	kind.resize(nn)
	var river := PackedFloat32Array()
	river.resize(nn)
	var rmask := PackedFloat32Array()
	rmask.resize(nn)
	var queue := PackedInt32Array()
	var have := PackedByteArray()
	have.resize(nn)
	for i in range(nn):
		var rb := ring_lab[i]
		if lab[i] == 0 and rb != 0 and kind_of[rb] == 3:
			river[i] = dem[i]
			have[i] = 1
			queue.append(i)
	var qi := 0
	while qi < queue.size():
		var i := queue[qi]
		qi += 1
		var x := i % n
		var y := i / n
		var bb := ring_lab[i] if lab[i] == 0 else lab[i]
		for nb in [i - 1 if x > 0 else -1, i + 1 if x < n - 1 else -1, i - n if y > 0 else -1, i + n if y < n - 1 else -1]:
			if nb < 0 or have[nb] == 1 or lab[nb] != bb or kind_of[bb] != 3:
				continue
			river[nb] = river[i]
			have[nb] = 1
			queue.append(nb)
	for i in range(nn):
		var b := lab[i]
		if b != 0 and kind_of[b] == 3:
			rmask[i] = 1.0
		else:
			river[i] = 0.0
	var any_river := false
	for b in range(1, count + 1):
		if kind_of[b] == 3:
			any_river = true
	if any_river:
		var sm := _blur(river, n, n, 3.0)
		var mm := _blur(rmask, n, n, 3.0)
		for i in range(nn):
			if rmask[i] > 0.0:
				river[i] = minf(river[i], sm[i] / maxf(mm[i], 1e-6)) - 0.25
	# the surface, the kind, and the bed carved under it
	var bed := dem.duplicate()
	var lev_sum := PackedFloat64Array()
	lev_sum.resize(count + 1)
	var lev_n := PackedInt32Array()
	lev_n.resize(count + 1)
	for i in range(nn):
		var b := lab[i]
		if b == 0:
			continue
		var k := kind_of[b]
		var s := river[i] if k == 3 else level_of[b]
		surface[i] = s
		kind[i] = k
		lev_sum[b] += s
		lev_n[b] += 1
		var depth := 0.0
		if k == 2:
			var deep := clampf(dmax[b] * 0.2, 2.0, 35.0)
			var t := clampf(d_in[i] / maxf(0.6 * dmax[b], 1.0), 0.0, 1.0)
			depth = 0.4 + deep * t * (2.0 - t)
		elif k == 3:
			depth = minf(0.4 + d_in[i] * 0.5, clampf(dmax[b] * 0.3, 0.8, 4.0))
		else:
			depth = minf(0.5 + d_in[i] * 0.05, 30.0)
		bed[i] = maxf(minf(dem[i], s - depth), s - 80.0)
	for b in range(1, count + 1):
		if kind_of[b] != 0 and lev_n[b] > 0:
			bodies.append({"id": b, "kind": ["", "sea", "lake", "river"][kind_of[b]],
					"level": snappedf(lev_sum[b] / lev_n[b], 0.01), "area_m2": lev_n[b] * 4,
					"half_width_m": snappedf(dmax[b], 0.1)})
	# the surface carried four cells onto the banks, the banks held up out of
	# the water, and a stream's channel where a lake's arm climbed away
	var near := surface.duplicate()
	for step in range(4):
		var nxt := near.duplicate()
		for i in range(nn):
			if not is_nan(near[i]):
				continue
			var x := i % n
			var y := i / n
			if y > 0 and not is_nan(near[i - n]):
				nxt[i] = near[i - n]
			elif y < n - 1 and not is_nan(near[i + n]):
				nxt[i] = near[i + n]
			elif x > 0 and not is_nan(near[i - 1]):
				nxt[i] = near[i - 1]
			elif x < n - 1 and not is_nan(near[i + 1]):
				nxt[i] = near[i + 1]
		near = nxt
	var stream := _blur(climb, n, n, 0.7)
	var height := PackedFloat32Array()
	height.resize(nn)
	for i in range(nn):
		if wmask[i] != 0:
			height[i] = bed[i]
			stream[i] = 0.0
		else:
			var st := clampf(stream[i], 0.0, 1.0)
			stream[i] = st
			var hgt := dem[i] - 0.6 * st
			if not is_nan(near[i]):
				hgt = maxf(hgt, near[i] + 0.2 + 0.12 * d_out[i])
			height[i] = hgt
	var kgrow := PackedInt32Array()
	kgrow.resize(nn)
	for i in range(nn):
		kgrow[i] = kind[i]
	kgrow = _grow(kgrow, n, n, 4)
	var kind_ext := PackedByteArray()
	kind_ext.resize(nn)
	for i in range(nn):
		kind_ext[i] = 0 if is_nan(near[i]) else kgrow[i]
	return {"height": height, "wmask": wmask, "kind": kind, "near": near, "kind_ext": kind_ext,
			"d_in": d_in, "d_out": d_out, "stream": stream, "bodies": bodies}


# ---------------------------------------------------- the layers, the plants

## The twelve layers (flat: layer * n4^2 + sample) and the four plant
## densities (tree, conifer, bush, grass, likewise), at 4 m.
func _layers_and_plants(dem: PackedFloat32Array, cover: Dictionary, w: Dictionary) -> Dictionary:
	var n := _n
	var n4 := _n4
	var nn := n4 * n4
	var slots: Array = cover.slots
	var f: PackedFloat32Array = cover.f
	var W := PackedFloat32Array()
	W.resize(12 * nn)
	for k in range(slots.size()):
		var lw: Dictionary = WC_LAYERS.get(int(slots[k]), {L_GRASS: 1.0})
		for lay in lw:
			var amt: float = lw[lay]
			var o: int = int(lay) * nn
			var fo := k * nn
			for s in range(nn):
				W[o + s] += amt * f[fo + s]
	# each layer softened a little
	for lay in range(12):
		var one := W.slice(lay * nn, (lay + 1) * nn)
		one = _box(one, n4, n4, 1)
		for s in range(nn):
			W[lay * nn + s] = one[s]
	# the slope (degrees) off the DEM, at 4 m
	var slope := PackedFloat32Array()
	slope.resize(nn)
	for j in range(n4):
		for i in range(n4):
			var x := 2 * i
			var y := 2 * j
			var xa := maxi(x - 1, 0)
			var xb := mini(x + 1, n - 1)
			var ya := maxi(y - 1, 0)
			var yb := mini(y + 1, n - 1)
			var gx := (dem[y * n + xb] - dem[y * n + xa]) / ((xb - xa) * RES)
			var gy := (dem[yb * n + x] - dem[ya * n + x]) / ((yb - ya) * RES)
			slope[j * n4 + i] = rad_to_deg(atan(sqrt(gx * gx + gy * gy)))
	slope = _box(slope, n4, n4, 1)
	var rough := _noise(n4, n4, 5.0, 21, 2)
	var height: PackedFloat32Array = w.height
	var wmask: PackedByteArray = w.wmask
	var kind: PackedByteArray = w.kind
	var near: PackedFloat32Array = w.near
	var kind_ext: PackedByteArray = w.kind_ext
	var d_in: PackedFloat32Array = w.d_in
	var d_out: PackedFloat32Array = w.d_out
	var stream: PackedFloat32Array = w.stream
	for s in range(nn):
		var g := (2 * (s / n4)) * n + 2 * (s % n4)
		var sl := slope[s]
		var steep := _smooth(36.0, 50.0, sl)
		var steep_snow := _smooth(52.0, 62.0, sl)
		var scree_slope := _smooth(28.0, 40.0, sl) * clampf(0.55 + 0.6 * rough[s], 0.0, 1.0) * (1.0 - steep)
		var rock_amt := steep_snow if W[L_SNOW * nn + s] > 0.5 else steep
		for lay in range(12):
			W[lay * nn + s] *= 1.0 - rock_amt
		W[L_ROCK * nn + s] += rock_amt
		var grassy := W[L_GRASS * nn + s] + W[L_DRY * nn + s] + W[L_MOSS * nn + s]
		var keep := 1.0 - scree_slope * 0.5
		W[L_GRASS * nn + s] *= keep
		W[L_DRY * nn + s] *= keep
		W[L_MOSS * nn + s] *= keep
		W[L_SCREE * nn + s] += grassy * scree_slope * 0.5
		# the shore: a beach on the sea, a pebble rim on a lake or a river
		var wet := wmask[g] != 0
		if not wet and not is_nan(near[g]) and height[g] < near[g] + 2.5:
			var a := clampf(1.0 - d_out[g] / 7.0, 0.0, 1.0) * 0.75
			var lay2 := L_SAND if kind_ext[g] == 1 else L_SCREE
			for lay in range(12):
				W[lay * nn + s] *= 1.0 - a
			W[lay2 * nn + s] += a
		var st := 0.85 * stream[g]
		if st > 0.0:
			for lay in range(12):
				W[lay * nn + s] *= 1.0 - st
			W[L_SCREE * nn + s] += st
		if wet:
			for lay in range(12):
				W[lay * nn + s] = 0.0
			if kind[g] == 1:
				var sbl := clampf(1.0 - d_in[g] / 60.0, 0.0, 1.0)
				W[L_SAND * nn + s] = sbl
				W[L_BED * nn + s] = 1.0 - sbl
			else:
				W[L_BED * nn + s] = 1.0
		var tot := 0.0
		for lay in range(12):
			var v := maxf(W[lay * nn + s], 0.0)
			W[lay * nn + s] = v
			tot += v
		tot = maxf(tot, 1e-6)
		for lay in range(12):
			W[lay * nn + s] /= tot
	# the plants
	var tree := _wcf(cover, [10])
	var mangrove := _wcf(cover, [95])
	for s in range(nn):
		tree[s] += 0.6 * mangrove[s]
	tree = _box(tree, n4, n4, 1)
	var shrub := _wcf(cover, [20])
	var alat := absf(_lat)
	var lo := clampf(1500.0 - 25.0 * (alat - 20.0), 0.0, 2600.0)
	var hi := lo + 700.0
	var cnoise := _noise(n4, n4, 20.0, 31, 2)
	var no_plant := PackedFloat32Array()
	no_plant.resize(nn)
	for s in range(nn):
		var g := (2 * (s / n4)) * n + 2 * (s % n4)
		no_plant[s] = clampf(float(wmask[g]) + W[L_ROCK * nn + s] + W[L_SNOW * nn + s]
				+ W[L_PAVING * nn + s] * 0.8 + W[L_SAND * nn + s], 0.0, 1.0)
		tree[s] = clampf(tree[s] * (1.0 - no_plant[s]) * (1.0 - _smooth(34.0, 46.0, slope[s])), 0.0, 1.0)
	var edge := _blur(tree, n4, n4, 2.0)
	var V := PackedFloat32Array()
	V.resize(4 * nn)
	for s in range(nn):
		var g := (2 * (s / n4)) * n + 2 * (s % n4)
		var guess := clampf(_smooth(lo, hi, dem[g]) + _smooth(52.0, 60.0, alat), 0.0, 1.0)
		var conifer := clampf(guess + 0.25 * cnoise[s], 0.0, 1.0)
		var e := clampf(edge[s] * (1.0 - tree[s]) * 3.0, 0.0, 1.0)
		var bush := 0.85 * shrub[s] + 0.12 * W[L_GRASS * nn + s] + 0.4 * e + 0.3 * W[L_MUD * nn + s] \
				+ 0.15 * W[L_MOSS * nn + s]
		bush = clampf(bush * (1.0 - no_plant[s]) * (1.0 - _smooth(38.0, 50.0, slope[s])), 0.0, 1.0)
		var grass := W[L_GRASS * nn + s] + 0.45 * W[L_SOIL * nn + s] + 0.85 * W[L_MUD * nn + s] \
				+ 0.5 * W[L_MOSS * nn + s] + 0.6 * W[L_DRY * nn + s] + 0.2 * W[L_FOREST * nn + s] \
				+ 0.25 * W[L_SCREE * nn + s]
		grass = clampf(grass * (1.0 - no_plant[s]), 0.0, 1.0)
		V[s] = tree[s]
		V[nn + s] = conifer
		V[2 * nn + s] = bush
		V[3 * nn + s] = grass
	return {"W": W, "V": V}


# ------------------------------------------------------------- out

## One grid file as EarthField reads it: MEWDGRD1, width, height (u32), type
## (u8: 1 u16, 2 u8, 3 f32), channels (u8), two pad bytes, the samples'
## length (u32), then the samples, deflated. Returns their SHA-256.
static func write_grid(path: String, raw: PackedByteArray, w: int, h: int, typ: int, ch: int) -> String:
	var head := "MEWDGRD1".to_ascii_buffer()
	var nums := PackedByteArray()
	nums.resize(16)
	nums.encode_u32(0, w)
	nums.encode_u32(4, h)
	nums.encode_u8(8, typ)
	nums.encode_u8(9, ch)
	nums.encode_u16(10, 0)
	nums.encode_u32(12, raw.size())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_buffer(head)
	f.store_buffer(nums)
	f.store_buffer(raw.compress(FileAccess.COMPRESSION_DEFLATE))
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(raw)
	return ctx.finish().hex_encode()


func _write(name: String, title: String, w: Dictionary, lv: Dictionary) -> String:
	var dir := dir_for(name)
	DirAccess.make_dir_recursive_absolute(dir)
	var n := _n
	var n4 := _n4
	var nn4 := n4 * n4
	var height: PackedFloat32Array = w.height
	var hmin := INF
	var hmax := -INF
	for v in height:
		hmin = minf(hmin, v)
		hmax = maxf(hmax, v)
	var scale := maxf((hmax - hmin) / 65000.0, 0.001)
	var hq := PackedByteArray()
	hq.resize(n * n * 2)
	for i in range(n * n):
		hq.encode_u16(i * 2, clampi(int(roundf((height[i] - hmin) / scale)), 0, 65535))
	var files := {}
	files["height.grid"] = write_grid(dir + "/height.grid", hq, n, n, 1, 1)
	# the water at 4 m: any water in the 2 m neighbourhood keeps a cell wet
	var near: PackedFloat32Array = w.near
	var kind_ext: PackedByteArray = w.kind_ext
	var w4 := PackedFloat32Array()
	w4.resize(nn4)
	var k4 := PackedByteArray()
	k4.resize(nn4)
	for j in range(n4):
		for i in range(n4):
			var v := NAN
			var k := 0
			for dy in [0, -1, 1]:
				for dx in [0, -1, 1]:
					var y: int = clampi(2 * j + dy, 0, n - 1)
					var x: int = clampi(2 * i + dx, 0, n - 1)
					var g := y * n + x
					if is_nan(v) and not is_nan(near[g]):
						v = near[g]
					if k == 0 and kind_ext[g] > 0:
						k = kind_ext[g]
			w4[j * n4 + i] = v
			k4[j * n4 + i] = 0 if is_nan(v) else k
	files["water.grid"] = write_grid(dir + "/water.grid", w4.to_byte_array(), n4, n4, 3, 1)
	files["wkind.grid"] = write_grid(dir + "/wkind.grid", k4, n4, n4, 2, 1)
	# the layers: three RGBA planes one above the other, four layers each
	var W: PackedFloat32Array = lv.W
	var cov := PackedByteArray()
	cov.resize(nn4 * 12)
	for plane in range(3):
		for s in range(nn4):
			var o := (plane * nn4 + s) * 4
			for c in range(4):
				cov[o + c] = clampi(int(roundf(W[(plane * 4 + c) * nn4 + s] * 255.0)), 0, 255)
	files["cover.grid"] = write_grid(dir + "/cover.grid", cov, n4, n4 * 3, 2, 4)
	var V: PackedFloat32Array = lv.V
	var veg := PackedByteArray()
	veg.resize(nn4 * 4)
	for s in range(nn4):
		for c in range(4):
			veg[s * 4 + c] = clampi(int(roundf(V[c * nn4 + s] * 255.0)), 0, 255)
	files["veg.grid"] = write_grid(dir + "/veg.grid", veg, n4, n4, 2, 4)
	for k in files:
		if String(files[k]) == "":
			error = "could not write %s/%s" % [dir, k]
			return ""
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	var keys := files.keys()
	keys.sort()
	for k in keys:
		ctx.update(String(files[k]).to_ascii_buffer())
	var region := {
		"name": name, "title": title, "lat": _lat, "lon": _lon, "size": _size,
		"datum": floorf(hmin - 1.0),
		"height": {"file": "height.grid", "n": n, "res": RES, "offset": hmin, "scale": scale,
			"min": snappedf(hmin, 0.01), "max": snappedf(hmax, 0.01)},
		"water": {"file": "water.grid", "kind": "wkind.grid", "n": n4, "res": RES * 2.0},
		"cover": {"file": "cover.grid", "n": n4, "res": RES * 2.0, "planes": 3, "layers": LAYERS},
		"veg": {"file": "veg.grid", "n": n4, "res": RES * 2.0, "channels": ["tree", "conifer", "bush", "grass"]},
		"bodies": w.bodies,
		"sources": {
			"height": "AWS Terrain Tiles, Terrarium, zoom %d (Mapzen: SRTM, GMTED, ETOPO1, national lidar)" % ZOOM,
			"cover": "ESA WorldCover 10 m 2021 v200 (CC BY 4.0)",
			"osm": "not used",
		},
		"attribution": "Height: Mapzen Terrain Tiles. Land cover: © ESA WorldCover project 2021 / "
				+ "Contains modified Copernicus Sentinel data (2021) processed by ESA WorldCover consortium.",
		"digest": ctx.finish().hex_encode().substr(0, 24),
		"made": Time.get_date_string_from_system(),
		"tool": "FENRIR's world map (RegionBuilder)",
	}
	var f := FileAccess.open(dir + "/region.json", FileAccess.WRITE)
	if f == null:
		error = "could not write %s/region.json" % dir
		return ""
	f.store_string(JSON.stringify(region, " "))
	return dir
