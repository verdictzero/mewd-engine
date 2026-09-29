## MEWD — spreading things procedurally (js/editor/scatter.js growScatter).
##
## A SCATTER is a rule the compiler runs every build: an area (a rect, a
## circle, or some sectors), what to put in it and in what proportions,
## how thick, how far apart, how clumped, and a seed. Darts are thrown
## from the seed; one that lands off the area, where nobody could stand,
## in a prop, or nearer than `spacing` to one already down is thrown
## away; a clump field (smooth value noise from the same seed) decides
## how likely one is kept where it landed. The same seed grows the same
## spread as the web build, dart for dart.
class_name Scatter

const SCATTER_MAX := 4000
const DENSITY_AREA := 1024.0 * 1024.0
const TYPES := ["SHOPPER", "TOWNIE", "TROLLEY", "BOLLARD", "FUELCAN", "CRATE", "STREETLAMP", "GRAVESTONE"]

## Math.imul, as an unsigned 32-bit result.
static func imul(a: int, b: int) -> int:
	a &= 0xFFFFFFFF
	b &= 0xFFFFFFFF
	var lo := (a * (b & 0xFFFF)) & 0xFFFFFFFF
	var hi := ((a * (b >> 16)) & 0xFFFF) << 16
	return (lo + hi) & 0xFFFFFFFF

static func hash2(x: int, y: int, seed: int) -> float:
	var h := imul(x, 374761393) ^ imul(y, 668265263) ^ imul(seed, 2246822519)
	h = imul(h ^ (h >> 13), 1274126177)
	h ^= h >> 16
	return float(h) / 4294967296.0

## Smooth value noise, two octaves, 0..1; the first 512 units across.
static func clump_at(x: float, y: float, seed: int) -> float:
	var v := 0.0
	var amp := 0.65
	var f := 1.0 / 512.0
	for o in 2:
		var gx := x * f
		var gy := y * f
		var ix := floori(gx)
		var iy := floori(gy)
		var tx := gx - ix
		var ty := gy - iy
		var sx := tx * tx * (3.0 - 2.0 * tx)
		var sy := ty * ty * (3.0 - 2.0 * ty)
		var s := seed + o * 101
		var a := hash2(ix, iy, s)
		var b := hash2(ix + 1, iy, s)
		var c := hash2(ix, iy + 1, s)
		var d := hash2(ix + 1, iy + 1, s)
		v += amp * (a + (b - a) * sx + (c - a) * sy + (a - b - c + d) * sx * sy)
		amp *= 0.35 / 0.65
		f *= 2.3
	return v

static func valid_type(type) -> bool:
	if not type is String:
		return false
	if type.begins_with("PLANT:"):
		return Forest.kind_index(type.substr(6)) >= 0
	return TYPES.has(type)

static func _jsround(v: float) -> int:
	return floori(v + 0.5)

## The area: {box: Rect2, size, has: Callable or null, sectors: {} or null}.
static func area_shape(area: Dictionary, rings: Dictionary) -> Dictionary:
	var kind := str(area.get("kind", ""))
	if kind == "circle":
		var c := Vector2(area.x, area.y)
		var r := float(area.r)
		return {"box": Rect2(c.x - r, c.y - r, 2 * r, 2 * r), "size": PI * r * r, "sectors": null,
			"has": func(x: float, y: float) -> bool: return (x - c.x) * (x - c.x) + (y - c.y) * (y - c.y) <= r * r}
	if kind == "rect":
		var x0 := minf(area.x0, area.x1)
		var x1 := maxf(area.x0, area.x1)
		var y0 := minf(area.y0, area.y1)
		var y1 := maxf(area.y0, area.y1)
		return {"box": Rect2(x0, y0, x1 - x0, y1 - y0), "size": (x1 - x0) * (y1 - y0), "sectors": null,
			"has": func(x: float, y: float) -> bool: return x >= x0 and x <= x1 and y >= y0 and y <= y1}
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	var size := 0.0
	var ids := {}
	var any := false
	for id in area.get("ids", []):
		ids[id] = true
		var r = rings.get(id)
		if r == null or r.size() < 3:
			continue
		any = true
		var a := 0.0
		for i in r.size():
			var p: Vector2 = r[i]
			var q: Vector2 = r[(i + 1) % r.size()]
			mn = mn.min(p)
			mx = mx.max(p)
			a += p.x * q.y - q.x * p.y
		size += absf(a) / 2.0
	var box := Rect2(mn, mx - mn) if any else Rect2()
	return {"box": box, "size": size, "sectors": ids, "has": null}

## Grow one scatter. ctx: rings ({id: ring}), standable (x, y -> the id
## of the document sector a thing could stand in there, or null),
## blocked (x, y, r -> inside a prop), taken (Array of Vector2, added to).
## Returns {items, wanted, grown}.
static func grow(sc: Dictionary, ctx: Dictionary) -> Dictionary:
	var shape := area_shape(sc.get("area", {"kind": "circle", "x": 0, "y": 0, "r": 0}), ctx.get("rings", {}))
	var items := []
	var total := 0.0
	for it in sc.get("items", []):
		if float(it.get("w", 0)) > 0 and valid_type(it.get("type")):
			items.append(it)
			total += float(it.w)
	var wanted := mini(SCATTER_MAX, maxi(0, _jsround(float(sc.get("density", 0)) * shape.size / DENSITY_AREA)))
	var out := []
	if total <= 0 or wanted <= 0 or not (shape.size > 0):
		return {"items": out, "wanted": wanted, "grown": 0}
	var seed := int(sc.get("seed", 1))
	var rnd := U.Rng.new((seed ^ imul(int(sc.get("id", 0)), 2654435761)) & 0xFFFFFFFF)
	var spacing := maxf(0.0, float(sc.get("spacing", 64)))
	var sp2 := spacing * spacing
	var clump := clampf(float(sc.get("clump", 0)), 0.0, 1.0)
	var box: Rect2 = shape.box
	var bx0 := box.position.x
	var by0 := box.position.y
	var bw := box.size.x
	var bh := box.size.y
	var cell := maxf(32.0, spacing)
	var buckets := {}
	var put := func(x: float, y: float) -> void:
		var k := Vector2i(floori(x / cell), floori(y / cell))
		if not buckets.has(k):
			buckets[k] = PackedVector2Array()
		buckets[k].append(Vector2(x, y))
	var taken: Array = ctx.get("taken", [])
	for p in taken:
		if p.x >= bx0 - spacing and p.x <= bx0 + bw + spacing and p.y >= by0 - spacing and p.y <= by0 + bh + spacing:
			put.call(p.x, p.y)
	var has = shape.has
	var sectors = shape.sectors
	var standable = ctx.get("standable")
	var blocked = ctx.get("blocked")
	var lo_s := float(sc.get("scaleMin", 1.0))
	var hi_s := float(sc.get("scaleMax", 1.0))
	var tries := wanted * 40 + 200
	var t := 0
	while t < tries and out.size() < wanted:
		t += 1
		var x := bx0 + rnd.next() * bw
		var y := by0 + rnd.next() * bh
		var keep := rnd.next()
		var pick_r := rnd.next()
		var ang_r := rnd.next()
		var var_r := rnd.next()
		var sc_r := rnd.next()
		if has != null and not has.call(x, y):
			continue
		var at = standable.call(x, y) if standable != null else 0
		if at == null:
			continue
		if sectors != null and not sectors.has(at):
			continue
		if blocked != null and blocked.call(x, y, 12.0):
			continue
		if clump > 0:
			var n := clump_at(x, y, seed + 7)
			var lo := 0.25 + clump * 0.3
			var hi := lo + 0.12 + (1.0 - clump) * 0.4
			var p := clampf((n - lo) / (hi - lo), 0.0, 1.0)
			if keep > p * p * (3.0 - 2.0 * p) + (1.0 - clump) * 0.15:
				continue
		if spacing > 0:
			var near := false
			var cx := floori(x / cell)
			var cy := floori(y / cell)
			for j in range(-1, 2):
				for i in range(-1, 2):
					var b = buckets.get(Vector2i(cx + i, cy + j))
					if b == null:
						continue
					for q in b:
						if (q.x - x) * (q.x - x) + (q.y - y) * (q.y - y) < sp2:
							near = true
							break
					if near:
						break
				if near:
					break
			if near:
				continue
		var r := pick_r * total
		var it: Dictionary = items[0]
		for i in items:
			r -= float(i.w)
			if r <= 0:
				it = i
				break
		var type: String = it.type
		var thing := {"type": type, "x": _jsround(x), "y": _jsround(y), "angle": ang_r * PI * 2.0,
			"variant": int(var_r * 64), "scale": float("%.3f" % (lo_s + (hi_s - lo_s) * sc_r)), "scatter": sc.get("id")}
		if type.begins_with("PLANT:"):
			thing.type = "PLANT"
			thing.kind = type.substr(6)
		out.append(thing)
		put.call(x, y)
		taken.append(Vector2(x, y))
	return {"items": out, "wanted": wanted, "grown": out.size()}
