class_name Cog
extends RefCounted

## JUST ENOUGH OF A CLOUD-OPTIMISED GEOTIFF READER for ESA WorldCover (and
## tiles like it), fetched a tile at a time by range request (GeoFetch):
## the first image, tiled, deflate or none, predictor 1 or 2, 8- or 16-bit
## integers or 32-bit floats, classic TIFF or BigTIFF, little- or
## big-endian. tools/earth_fetch.py's COG, in GDScript.

var url := ""
var ok := false
var w := 0
var h := 0
var tw := 0
var th := 0
var bits := 8
var fmt := 1
var comp := 1
var pred := 1
var across := 0
## longitude / latitude of pixel (0, 0)'s centre, and degrees a pixel
var x0 := 0.0
var y0 := 0.0
var sx := 1.0
var sy := 1.0
var nodata := 0.0

var _head := PackedByteArray()
var _le := true
var _big := false
var _offsets: Array = []
var _counts: Array = []
var _tiles := {}


## Open `url`; `ok` false when there is no such file (a WorldCover tile over
## open sea) or it is not one this reads.
func _init(u: String) -> void:
	url = u
	var r := GeoFetch.get_url(url, 0, 65536)
	if not r.ok:
		return
	_head = r.body
	if _head.size() < 16:
		return
	_le = _head[0] == 0x49
	var magic := _u16(_head, 2)
	_big = magic == 43
	var ifd := _u64(_head, 8) if _big else _u32(_head, 4)
	var t := _ifd(ifd)
	if t.is_empty():
		return
	w = int(t[256][0])
	h = int(t[257][0])
	if not t.has(322):
		return
	tw = int(t[322][0])
	th = int(t[323][0])
	bits = int(t[258][0])
	fmt = int(t.get(339, [1])[0])
	comp = int(t.get(259, [1])[0])
	pred = int(t.get(317, [1])[0])
	_offsets = t[324]
	_counts = t[325]
	across = (w + tw - 1) / tw
	var scale: Array = t.get(33550, [1.0, 1.0])
	var tie: Array = t.get(33922, [0, 0, 0, 0, 0, 0])
	sx = float(scale[0])
	sy = float(scale[1])
	# GTRasterTypeGeoKey (1025) 2: the tiepoint is a pixel's centre
	var point := false
	var keys: Array = t.get(34735, [])
	for k in range(4, keys.size() - 3, 4):
		if int(keys[k]) == 1025 and int(keys[k + 3]) == 2:
			point = true
	x0 = float(tie[3]) - float(tie[0]) * sx + (0.0 if point else 0.5 * sx)
	y0 = float(tie[4]) + float(tie[1]) * sy - (0.0 if point else 0.5 * sy)
	var nd: Variant = t.get(42113, "")
	if nd is String and String(nd).strip_edges() != "":
		nodata = float(String(nd).strip_edges())
	ok = comp in [1, 8, 32946] and pred in [1, 2] and bits in [8, 16, 32]


## Pixels [c0, c1) x [r0, r1), clipped to the image: {"data":
## PackedFloat32Array row by row, "w", "h", "c0", "r0"}.
func window(c0: int, r0: int, c1: int, r1: int) -> Dictionary:
	c0 = maxi(c0, 0)
	r0 = maxi(r0, 0)
	c1 = mini(c1, w)
	r1 = mini(r1, h)
	var ww := maxi(c1 - c0, 0)
	var hh := maxi(r1 - r0, 0)
	var out := PackedFloat32Array()
	out.resize(ww * hh)
	if ww == 0 or hh == 0:
		return {"data": out, "w": ww, "h": hh, "c0": c0, "r0": r0}
	for ty in range(r0 / th, (r1 - 1) / th + 1):
		for tx in range(c0 / tw, (c1 - 1) / tw + 1):
			var t: PackedFloat32Array = tile(tx, ty)
			var ys := ty * th
			var xs := tx * tw
			var a0 := maxi(r0, ys)
			var a1 := mini(r1, ys + th)
			var b0 := maxi(c0, xs)
			var b1 := mini(c1, xs + tw)
			for y in range(a0, a1):
				var src := (y - ys) * tw + (b0 - xs)
				var dst := (y - r0) * ww + (b0 - c0)
				for x in range(b1 - b0):
					out[dst + x] = t[src + x]
	return {"data": out, "w": ww, "h": hh, "c0": c0, "r0": r0}


## One tile's pixels, tw x th, as floats.
func tile(tx: int, ty: int) -> PackedFloat32Array:
	var k := Vector2i(tx, ty)
	if _tiles.has(k):
		return _tiles[k]
	var i := ty * across + tx
	var a := PackedFloat32Array()
	a.resize(tw * th)
	var off := int(_offsets[i]) if i < _offsets.size() else 0
	var cnt := int(_counts[i]) if i < _counts.size() else 0
	if cnt == 0:
		a.fill(nodata)
	else:
		var r := GeoFetch.get_url(url, off, cnt)
		var raw: PackedByteArray = r.body
		var bps := bits / 8
		if comp != 1:
			raw = raw.decompress(tw * th * bps, FileAccess.COMPRESSION_DEFLATE)
		if raw.size() < tw * th * bps:
			a.fill(nodata)
		else:
			_decode(raw, a, bps)
	_tiles[k] = a
	return a


func _decode(raw: PackedByteArray, a: PackedFloat32Array, bps: int) -> void:
	var n := tw * th
	if bps == 1:
		for p in range(n):
			a[p] = raw[p]
	elif bps == 2:
		for p in range(n):
			var v := _u16(raw, p * 2)
			if fmt == 2 and v >= 32768:
				v -= 65536
			a[p] = v
	else:
		for p in range(n):
			if fmt == 3:
				a[p] = raw.decode_float(p * 4) if _le else _swap32f(raw, p * 4)
			else:
				a[p] = _u32(raw, p * 4)
	if pred == 2:
		for y in range(th):
			var row := y * tw
			for x in range(1, tw):
				a[row + x] += a[row + x - 1]
				if bps == 1:
					a[row + x] = fmod(a[row + x], 256.0)


func _swap32f(b: PackedByteArray, o: int) -> float:
	var t := PackedByteArray([b[o + 3], b[o + 2], b[o + 1], b[o]])
	return t.decode_float(0)


func _bytes(off: int, n: int) -> PackedByteArray:
	if off + n <= _head.size():
		return _head.slice(off, off + n)
	return GeoFetch.get_url(url, off, n).body


func _u16(b: PackedByteArray, o: int) -> int:
	return b.decode_u16(o) if _le else (b[o] << 8) | b[o + 1]


func _u32(b: PackedByteArray, o: int) -> int:
	return b.decode_u32(o) if _le else (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3]


func _u64(b: PackedByteArray, o: int) -> int:
	return b.decode_u64(o) if _le else (_u32(b, o) << 32) | _u32(b, o + 4)


# the tags of the IFD at `off`: {tag: [values]} (ASCII as one String)
func _ifd(off: int) -> Dictionary:
	var cnt: int
	var esz: int
	var base: int
	if _big:
		cnt = _u64(_bytes(off, 8), 0)
		esz = 20
		base = off + 8
	else:
		cnt = _u16(_bytes(off, 2), 0)
		esz = 12
		base = off + 2
	var raw := _bytes(base, cnt * esz)
	if raw.size() < cnt * esz:
		return {}
	var sizes := {1: 1, 2: 1, 3: 2, 4: 4, 5: 8, 6: 1, 8: 2, 9: 4, 11: 4, 12: 8, 16: 8, 17: 8}
	var tags := {}
	for i in range(cnt):
		var e := i * esz
		var tag := _u16(raw, e)
		var typ := _u16(raw, e + 2)
		var n: int = _u64(raw, e + 4) if _big else _u32(raw, e + 4)
		var inline := 8 if _big else 4
		var vo := e + (12 if _big else 8)
		if not sizes.has(typ):
			continue
		var total: int = sizes[typ] * n
		var data: PackedByteArray
		if total <= inline:
			data = raw.slice(vo, vo + total)
		else:
			var p: int = _u64(raw, vo) if _big else _u32(raw, vo)
			data = _bytes(p, total)
		var vals := []
		match typ:
			2:
				var txt := ""
				for k in range(data.size()):
					if data[k] != 0:
						txt += char(data[k])
				tags[tag] = txt
				continue
			1, 6:
				for k in range(n):
					vals.append(data[k])
			3, 8:
				for k in range(n):
					vals.append(_u16(data, k * 2))
			4, 9:
				for k in range(n):
					vals.append(_u32(data, k * 4))
			16, 17:
				for k in range(n):
					vals.append(_u64(data, k * 8))
			5:
				for k in range(n):
					var num := _u32(data, k * 8)
					var den := _u32(data, k * 8 + 4)
					vals.append(float(num) / maxf(den, 1))
			11:
				for k in range(n):
					vals.append(data.decode_float(k * 4))
			12:
				for k in range(n):
					vals.append(data.decode_double(k * 8))
		tags[tag] = vals
	return tags
