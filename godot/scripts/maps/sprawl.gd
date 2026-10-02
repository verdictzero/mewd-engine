## MEWD — THE SPRAWL, the game's own world (js/maps/sprawl.js).
##
## A sprawling level made of all the assets the user has given and none
## that were generated: sixteen blocks, four by four, 3200 units a side,
## roads 768 wide between them, on a floor sunk 686 units into a grass
## plateau whose inner face is the pack's lawn-topped cliff, with the
## pack's painted horizons standing on the plateau against the sky. Each
## block is a district and each district one part of the texture pack
## — the park, the car park, the cube farm, the plaza, the cemetery, the
## ops centre, the mansion, the market, the wood, the quarry, the
## brutalist hall, the yard, the meadow, the test chamber, the lake and
## the ruins — and the start is the crossroads in the middle.
##
## A MAP IN BLOCKS (BlockDoc, for BlockCompile; at the user's request,
## with the rest of the levels): the roads are the ground plane itself,
## the plateau four blocks 686 high round them, and every piece of a
## district a block on what it is drawn inside — a pavement a block 8
## high, a lawn a patch on it, a pond a block pushed down into the lawn,
## a hedge a block on it. Each piece is still drawn with the height of
## its top as the web build's document had it (`floor`), a ring strictly
## inside its parent, and made relative at the end
## (BlockDoc.relative_heights). A BUILDING is its floor, four wall
## blocks round it cut at the doors with a lintel block floating over
## each, a working door (BlockCompile's) in every doorway with a door
## texture, and a roof slab on the layer over (with a hole where a
## courtyard or a light well is open to the sky). What were free boxes
## (props: desks, panels, cubicles, the stones of the circle) are blocks
## floating at their own base.
class_name SprawlMap

const NAME := "THE SPRAWL"
const BLOCK := 3200
const ROAD := 768
const RIM := 512
const CLIFF_H := 686
const SIZE := 2 * RIM + 5 * ROAD + 4 * BLOCK
const CURB := 8
const DOOR_W := 64
const DOOR_H := 128
const WALL_T := BlockDoc.WALL_T
const SLAB := 16.0

const FIRS := ["fir_tall_1", "fir_tall_2", "fir_medium", "fir_young"]
const STREET := ["street_round", "street_broad", "street_oval", "street_upright", "street_dense", "street_big"]

static func block_at(i: int) -> int:
	return RIM + ROAD + i * (BLOCK + ROAD)

static func start() -> Vector2:
	return Vector2(block_at(2) - ROAD / 2.0, block_at(2) - ROAD / 2.0)

# ------------------------------------------------------------------
# THE PIECES, as js/maps/sprawl.js has them, over one document in blocks
# ------------------------------------------------------------------
class B extends BlockDoc:
	var rng := U.Rng.new(20260926)

	func _init() -> void:
		var w := DocCompile.default_world()
		w.merge({
			"skybox": "BSKY2",
			"lightColor": "#fff0dc",
			"ambient": {"color": "#302418", "amount": 0.25},
			"fog": {"color": "#b8a488", "density": 2},
			"fogAmbient": 0.5,
		}, true)
		super(NAME, {"tex": "ASPHALT1", "light": 1.0}, w)

	func rnd() -> float:
		return rng.next()

	func pick(a: Array):
		return a[int(rnd() * a.size())]

	static func jr(x: float) -> int:
		return floori(x + 0.5)

	## A PIECE OF GROUND: a block over the ring, the height of its top
	## `floor` (made relative at the end), its top `floorTex`, its sides
	## `lowerTex` (or `wallTex`), the air over it lit by `light`.
	func sector(pts: Array, props: Dictionary) -> Dictionary:
		var side = _or(props.get("lowerTex"), _or(props.get("wallTex"), "CONC_2"))
		var p := {"floor": float(props.get("floor", 0)), "top": _or(props.get("floorTex"), "LAWN2"), "side": side,
			"name": props.get("name", ""), "air": float(props.get("light", 0.72))}
		return block(pts, p)

	static func _or(x, dflt):
		return dflt if x == null or (x is String and x == "") else x

	static func box(x0: float, y0: float, x1: float, y1: float) -> Array:
		return BlockDoc.rect_pts(x0, y0, x1, y1)

	static func octagon(cx: float, cy: float, r: float, n := 8, turn = null) -> Array:
		return BlockDoc.ngon(cx, cy, r, n, turn)

	static func edges(pts: Array) -> Array:
		var out := []
		for i in pts.size():
			out.append([pts[i], pts[(i + 1) % pts.size()]])
		return out

	func plant(kind: String, x: float, y: float, scale := 1.0) -> void:
		thing("PLANT", x, y, {"kind": kind, "scale": scale})

	## A FREE BOX: a block floating at z0, up to z1, its sides `tex`.
	func prop(x0: float, y0: float, x1: float, y1: float, z0: float, z1: float, tex: String, top_tex = null) -> void:
		rect(jr(x0), jr(y0), jr(x1), jr(y1), {"base": z0, "h": z1 - z0, "side": tex, "under": tex,
			"top": tex if top_tex == null else top_tex, "name": "prop"})

	func scatter(area: Dictionary, items: Array, density: float, spacing: float, clump := 0.3, extra := {}) -> void:
		var e := extra.duplicate()
		e["seed"] = int(rnd() * 1e6)
		super(area, items, density, spacing, clump, e)

	## A BUILDING: its floor (a block the height of `floor`), four WALL
	## BLOCKS round it, WALL_T thick, up to `ceil`, their inside in
	## `wallTex` (a skin on each wall's inner edge) and their outside the
	## `facade`; each cut at its DOORS, a lintel block floating over the
	## gap from the door's head, and a door in the gap where the door has
	## a texture (an open doorway where not); and, unless it is open to
	## the sky, a ROOF slab on the layer over, its underside `ceilTex`,
	## lighting the room with `light` — round a `hole` [x0, y0, x1, y1]
	## where something inside it stands in the open.
	func building(x0: float, y0: float, x1: float, y1: float, props: Dictionary, doors: Array = [], _outside = null) -> Dictionary:
		var f: float = props.get("floor", CURB)
		var top: float = props.get("ceil", f + 256)
		var facade: String = props.get("facade", "CONC_1")
		var wall_tex: String = _or(props.get("wallTex"), facade)
		var roof_tex: String = props.get("roofTex", "CONC_3")
		var ceil_tex: String = _or(props.get("ceilTex"), roof_tex)
		var door_h: float = props.get("doorH", DOOR_H)
		var light: float = props.get("light", 0.72)
		var nm: String = props.get("name", "")
		var T := WALL_T
		var fl := rect(x0, y0, x1, y1, {"floor": f, "top": _or(props.get("floorTex"), "CONC_2"), "side": facade, "name": nm, "air": light})
		for side in ["s", "e", "n", "w"]:
			var horiz: bool = side == "s" or side == "n"
			var lo: float = x0 - T if horiz else y0
			var hi: float = x1 + T if horiz else y1
			var across := [y0 - T, y0] if side == "s" else ([y1, y1 + T] if side == "n" else ([x0 - T, x0] if side == "w" else [x1, x1 + T]))
			var inner: float = y0 if side == "s" else (y1 if side == "n" else (x0 if side == "w" else x1))
			var ds := []
			for g in doors:
				if g.side == side:
					var gw: float = g.get("w", DOOR_W)
					ds.append({"lo": g.at - gw / 2.0, "hi": g.at + gw / 2.0, "h": float(g.get("h", door_h)), "tex": g.get("tex")})
			ds.sort_custom(func(p, q): return p.lo < q.lo)
			var strip := func(a: float, c: float, p: Dictionary) -> Dictionary:
				return rect(a, across[0], c, across[1], p) if horiz else rect(across[0], a, across[1], c, p)
			var at := lo
			var wall := {"floor": top, "top": facade, "side": facade, "name": nm + " wall"}
			for g in ds:
				if g.lo > at:
					strip.call(at, g.lo, wall)
				strip.call(g.lo, g.hi, {"base": f + g.h, "h": top - (f + g.h), "top": facade, "side": facade, "under": facade, "name": nm + " lintel"})
				var p := Vector2(g.lo, inner) if horiz else Vector2(inner, g.lo)
				var q := Vector2(g.hi, inner) if horiz else Vector2(inner, g.hi)
				if g.tex != null:
					line(p, q, {"door": {"h": g.h, "tex": g.tex}})
				at = g.hi
			if at < hi:
				strip.call(at, hi, wall)
			# the room's own side of the wall
			var ia := maxf(lo, x0 if horiz else y0)
			var ib := minf(hi, x1 if horiz else y1)
			line(Vector2(ia, inner) if horiz else Vector2(inner, ia), Vector2(ib, inner) if horiz else Vector2(inner, ib), {"tex": wall_tex})
		if not props.get("outdoor", false):
			var roof := {"base": top, "h": SLAB, "top": roof_tex, "under": ceil_tex, "side": facade, "light": light, "name": nm + " roof"}
			on(1)
			var hole = props.get("hole")
			if hole == null:
				rect(x0 - T, y0 - T, x1 + T, y1 + T, roof)
			else:
				rect(x0 - T, y0 - T, x1 + T, hole[1], roof)
				rect(x0 - T, hole[3], x1 + T, y1 + T, roof)
				rect(x0 - T, hole[1], hole[0], hole[3], roof)
				rect(hole[2], hole[1], x1 + T, hole[3], roof)
			on(0)
		return fl

	## A SIGN: a picture standing in one edge of a slot of ground, masked.
	func sign(x0: float, y0: float, x1: float, y1: float, tex: String, floor: float, face := "s", props := {}) -> Dictionary:
		var p := {"floor": floor, "floorTex": "CONC_2", "lowerTex": "CONC_2", "light": 0.8}
		p.merge(props, true)
		var s := sector(box(x0, y0, x1, y1), p)
		var E: Array = {"s": [Vector2(x0, y0), Vector2(x1, y0)], "n": [Vector2(x1, y1), Vector2(x0, y1)],
			"w": [Vector2(x0, y1), Vector2(x0, y0)], "e": [Vector2(x1, y0), Vector2(x1, y1)]}[face]
		line(E[0], E[1], {"midTex": tex, "blocking": true})
		return s

	## A WALL PANEL: a picture hung flat on a wall as a thin box.
	func panel(x: float, y: float, w: float, z0: float, h: float, tex: String, along := "x", thick := 12.0) -> void:
		if along == "x":
			prop(x, y, x + w, y + thick, z0, z0 + h, tex, tex)
		else:
			prop(x, y, x + thick, y + w, z0, z0 + h, tex, tex)

## Build THE SPRAWL. Pure, and the same every time.
static func build() -> Dictionary:
	var b := B.new()
	var S := SIZE
	var R := RIM
	# ---- THE PLATEAU, THE CLIFF AND THE HORIZON: the roads are the
	# ground; the plateau four blocks round them, their inner faces the
	# cliff
	var plateau := {"name": "the plateau", "floor": CLIFF_H, "floorTex": "GRASS5", "lowerTex": "CLIFF2", "light": 0.84}
	b.sector(B.box(0, 0, R, S), plateau)
	b.sector(B.box(S - R, 0, S, S), plateau)
	b.sector(B.box(R, 0, S - R, R), plateau)
	b.sector(B.box(R, S - R, S - R, S), plateau)
	var VG := 160
	for q in [[R + 1, R + 1, S - R - 1, R + VG], [R + 1, S - R - VG, S - R - 1, S - R - 1],
			[R + 1, R + VG + 1, R + VG, S - R - VG - 1], [S - R - VG, R + VG + 1, S - R - 1, S - R - VG - 1]]:
		var vg := b.sector(B.box(q[0], q[1], q[2], q[3]), {"name": "verge", "floor": 0, "floorTex": "DIRT_01", "lowerTex": "DIRT_02", "light": 0.9})
		b.scatter(B.in_blocks([vg]), B.items(["PLANT:grass", 5, "PLANT:fern", 3, "PLANT:bush_small_1", 1]), 30, 40, 0.6, {"name": "verge grass"})
	var third := (S - 2.0 * R) / 3.0
	var horizon := func(side: String, k: int, near, far) -> void:
		var ns := side == "n" or side == "s"
		var a: float = R + k * third - (96 if ns and k == 0 else 0)
		var bb: float = R + (k + 1) * third + (96 if ns and k == 2 else 0)
		var at := func(off: float, w: float, tex: String) -> void:
			var P := {"name": "horizon", "floorTex": "GRASS5", "wallTex": "GRASS5", "lowerTex": "NONE", "light": 0.84}
			var fl := float(CLIFF_H)
			if side == "n":
				b.sign(a, S - R + off, bb, S - R + off + w, tex, fl, "s", P)
			elif side == "s":
				b.sign(a, R - off - w, bb, R - off, tex, fl, "n", P)
			elif side == "e":
				b.sign(S - R + off, a, S - R + off + w, bb, tex, fl, "w", P)
			else:
				b.sign(R - off - w, a, R - off, bb, tex, fl, "e", P)
		if near != null:
			at.call(48, 24, near)
		if far != null:
			at.call(200, 24, far)
	horizon.call("n", 0, "TREEBACK", null); horizon.call("n", 1, "TREELINE", "MOUNTBG"); horizon.call("n", 2, "MEADOWBG", null)
	horizon.call("s", 0, "TREELINE", "MOUNTBG"); horizon.call("s", 1, "RUINLINE", "MNTN0001"); horizon.call("s", 2, "TREELINE", "MOUNTBG")
	horizon.call("e", 0, "MEADOWBG", null); horizon.call("e", 1, "TREEBACK", null); horizon.call("e", 2, "TREELINE", "MNTN0001")
	horizon.call("w", 0, "TREEBACK", null); horizon.call("w", 1, "TREELINE", "MOUNTBG"); horizon.call("w", 2, "MEADOWBG", null)
	var t := R + 256
	while t < S - R - 256:
		for xy in [[t, R - 96], [t, S - R + 96], [R - 96, t], [S - R + 96, t]]:
			var kind: String = b.pick(FIRS)
			var px: float = xy[0] + (b.rnd() - 0.5) * 120
			var py: float = xy[1] + (b.rnd() - 0.5) * 60
			b.plant(kind, px, py, 1 + b.rnd() * 0.3)
		t += 640

	# ---- THE BLOCKS: a pavement each, lamps and street trees round it
	var blocks := []
	for j in 4:
		for i in 4:
			var x0 := block_at(i)
			var y0 := block_at(j)
			var x1 := x0 + BLOCK
			var y1 := y0 + BLOCK
			var walk := b.sector(B.box(x0, y0, x1, y1), {"name": "pavement %d,%d" % [i, j], "floor": CURB, "ceil": CLIFF_H,
				"floorTex": "SIDEWLK1", "wallTex": "CONC_2", "lowerTex": "CONC_2", "light": 0.8})
			blocks.append({"i": i, "j": j, "x0": x0, "y0": y0, "x1": x1, "y1": y1, "walk": walk,
				"ix0": x0 + 192, "iy0": y0 + 192, "ix1": x1 - 192, "iy1": y1 - 192})
			var step := 800
			var tt := step / 2
			while tt < BLOCK:
				b.thing("STREETLAMP", x0 + tt, y0 + 48, {"angle": -PI / 2})
				b.thing("STREETLAMP", x0 + tt, y1 - 48, {"angle": PI / 2})
				b.thing("STREETLAMP", x0 + 48, y0 + tt, {"angle": PI})
				b.thing("STREETLAMP", x1 - 48, y0 + tt, {"angle": 0.0})
				if tt + step / 2 < BLOCK and absf(tt + step / 2.0 - BLOCK / 2.0) > 200:
					b.plant(b.pick(STREET), x0 + tt + step / 2, y0 + 96)
					b.plant(b.pick(STREET), x0 + tt + step / 2, y1 - 96)
					b.plant(b.pick(STREET), x0 + 96, y0 + tt + step / 2)
					b.plant(b.pick(STREET), x1 - 96, y0 + tt + step / 2)
				tt += step
	var BL := func(i: int, j: int) -> Dictionary: return blocks[j * 4 + i]
	# THE ROAD MARKINGS
	var road_mid := func(k: int) -> float: return R + ROAD / 2.0 if k == 0 else block_at(k - 1) + BLOCK + ROAD / 2.0
	for k in 5:
		var c: float = road_mid.call(k)
		for m in 4:
			var lo := block_at(m)
			var hi := lo + BLOCK
			var tt := lo + 160
			while tt + 192 < hi - 160:
				if absf(tt + 96 - (lo + BLOCK / 2.0)) >= 256:
					b.sector(B.box(c - 16, tt, c + 16, tt + 192), {"name": "road line", "floor": 0, "floorTex": "OFCCEIL1", "lowerTex": "CONC_2", "light": 1.1})
					b.sector(B.box(tt, c - 16, tt + 192, c + 16), {"name": "road line", "floor": 0, "floorTex": "OFCCEIL1", "lowerTex": "CONC_2", "light": 1.1})
				tt += 448
	var st := start()
	b.sector(B.box(st.x - 256, st.y - 256, st.x + 256, st.y + 256), {"name": "box junction", "floor": 0, "floorTex": "PARKLOT3", "lowerTex": "CONC_2", "light": 1.0})
	for k in 5:
		if k == 0 or k == 4:
			continue
		var r := block_at(k - 1) + BLOCK
		for m in 4:
			var c := block_at(m) + BLOCK / 2
			b.sector(B.box(c - 96, r + 16, c + 96, r + ROAD - 16), {"name": "crossing", "floor": 0, "floorTex": "SIDEWLK1", "lowerTex": "CONC_2", "light": 0.8})
			b.sector(B.box(r + 16, c - 96, r + ROAD - 16, c + 96), {"name": "crossing", "floor": 0, "floorTex": "SIDEWLK1", "lowerTex": "CONC_2", "light": 0.8})

	_park(b, BL.call(0, 0))
	_car_park(b, BL.call(1, 0))
	_cube_farm(b, BL.call(2, 0))
	_plaza(b, BL.call(3, 0))
	_cemetery(b, BL.call(0, 1))
	_ops(b, BL.call(1, 1))
	_mansion(b, BL.call(2, 1))
	_market(b, BL.call(3, 1))
	_wood(b, BL.call(0, 2))
	_quarry(b, BL.call(1, 2))
	_hall(b, BL.call(2, 2))
	_yard(b, BL.call(3, 2))
	_meadow(b, BL.call(0, 3))
	_lab(b, BL.call(1, 3))
	_lake(b, BL.call(2, 3))
	_ruins(b, BL.call(3, 3))

	# ---- THE CROSSROADS, and the start
	b.thing("START", st.x, st.y, {"angle": PI / 2})
	b.scatter(B.in_rect(R + ROAD, st.y - 256, S - R - ROAD, st.y + 256), B.items(["TOWNIE", 1]), 0.8, 320, 0.3, {"name": "road walkers e-w"})
	b.scatter(B.in_rect(st.x - 256, R + ROAD, st.x + 256, S - R - ROAD), B.items(["TOWNIE", 1]), 0.8, 320, 0.3, {"name": "road walkers n-s"})
	_beds(b, BL.call(0, 3))
	b.relative_heights()
	var d := b.out()
	d["size"] = S
	return d

# ---- 0,0 THE PARK
static func _park(b: B, k: Dictionary) -> void:
	var cx: float = (k.ix0 + k.ix1) / 2.0
	var cy: float = (k.iy0 + k.iy1) / 2.0
	var lawn := b.sector(B.box(k.ix0, k.iy0, k.ix1, k.iy1), {"name": "park lawn", "floor": CURB, "floorTex": "LAWNTEST", "lowerTex": "DIRT_02", "wallTex": "DIRT_02", "light": 0.84})
	for q in [[k.ix0 + 32, cy - 64, cx - 640, cy + 64], [cx + 640, cy - 64, k.ix1 - 32, cy + 64], [cx - 64, k.iy0 + 32, cx + 64, cy - 640], [cx - 64, cy + 640, cx + 64, k.iy1 - 32]]:
		b.sector(B.box(q[0], q[1], q[2], q[3]), {"name": "path", "floor": CURB, "floorTex": "XTX_1", "lowerTex": "CONC_2", "light": 0.84})
	b.sector(B.octagon(cx, cy, 640), {"name": "pond paving", "floor": CURB, "floorTex": "XTX_1", "lowerTex": "CONC_2", "light": 0.84})
	b.sector(B.octagon(cx, cy, 520), {"name": "pond bank", "floor": CURB - 4, "floorTex": "DIRT_01", "lowerTex": "DIRT_02", "wallTex": "DIRT_02", "light": 0.82})
	b.sector(B.octagon(cx, cy, 440), {"name": "pond", "floor": -20, "floorTex": "WAT201", "lowerTex": "ROCK_01", "wallTex": "ROCK_01", "light": 0.72})
	var x0: float = k.ix0
	var y0: float = k.iy0
	var x1: float = k.ix1
	var y1: float = k.iy1
	for h in [[x0 + 256, y0 + 256, x0 + 1088, y0 + 320], [x1 - 1088, y0 + 256, x1 - 256, y0 + 320],
			[x0 + 256, y1 - 320, x0 + 1088, y1 - 256], [x1 - 1088, y1 - 320, x1 - 256, y1 - 256],
			[x0 + 256, y0 + 320, x0 + 320, y0 + 1088], [x1 - 320, y0 + 320, x1 - 256, y0 + 1088],
			[x0 + 256, y1 - 1088, x0 + 320, y1 - 320], [x1 - 320, y1 - 1088, x1 - 256, y1 - 320]]:
		b.sector(B.box(h[0], h[1], h[2], h[3]), {"name": "hedge", "floor": CURB + 56, "floorTex": "IVY1", "lowerTex": "IVY1", "wallTex": "IVY1", "light": 0.8})
	var trees := []
	for s in STREET:
		trees.append({"type": "PLANT:" + s, "w": 2})
	trees.append_array(B.items(["PLANT:fir_medium", 2, "PLANT:bush_large_1", 3, "PLANT:bush_small_2", 2]))
	b.scatter(B.in_blocks([lawn]), trees, 5, 220, 0.4, {"name": "park trees", "scaleMin": 0.85, "scaleMax": 1.15})
	b.scatter(B.in_blocks([lawn]), B.items(["TOWNIE", 3, "SHOPPER", 1]), 3, 180, 0.2, {"name": "strollers"})

# ---- 1,0 THE CAR PARK
static func _car_park(b: B, k: Dictionary) -> void:
	var lot := b.sector(B.box(k.ix0, k.iy0, k.ix1, k.iy1), {"name": "car park", "floor": CURB, "floorTex": "PARKLOT1", "lowerTex": "CONC_3", "wallTex": "CONC_3", "light": 0.8})
	for c in 4:
		var x: float = k.ix0 + 320 + c * 640
		b.sector(B.box(x, k.iy0 + 192, x + 256, k.iy1 - 640), {"name": "bays", "floor": CURB, "floorTex": "PARKLOT2", "lowerTex": "CONC_3", "light": 0.8})
	b.sector(B.box(k.ix0 + 192, k.iy0 + 64, k.ix1 - 192, k.iy0 + 160), {"name": "no parking", "floor": CURB, "floorTex": "PARKLOT3", "lowerTex": "CONC_3", "light": 0.8})
	b.sector(B.box(k.ix0 + 128, k.iy1 - 512, k.ix1 - 128, k.iy1 - 480), {"name": "hazard strip", "floor": CURB + 4, "floorTex": "CAUTSTR2", "lowerTex": "CAUTSTR2", "light": 0.8})
	var kx0: float = k.ix1 - 640
	var ky0: float = k.iy1 - 384
	var kx1: float = k.ix1 - 128
	var ky1: float = k.iy1 - 128
	b.building(kx0, ky0, kx1, ky1, {"name": "kiosk", "floor": CURB, "ceil": CURB + 160, "floorTex": "CONC_5", "ceilTex": "CONC_5", "wallTex": "CONC_2", "facade": "CONC_5", "roofTex": "METALP1", "light": 0.7},
		[{"side": "n", "at": kx0 + 128, "tex": "DR1_01"}], lot)
	b.panel(kx0 + 128, ky0 - WALL_T - 12, 128, CURB, 128, "DOOR0001"); b.panel(kx0 + 256, ky0 - WALL_T - 12, 128, CURB, 128, "DOOR0001")
	b.scatter(B.in_blocks([lot]), B.items(["SHOPPER", 3, "TOWNIE", 1]), 5, 150, 0.4, {"name": "shoppers"})

# ---- 2,0 THE CUBE FARM
static func _cube_farm(b: B, k: Dictionary) -> void:
	var x0: float = k.ix0 + 128
	var y0: float = k.iy0 + 128
	var x1: float = k.ix1 - 128
	var y1: float = k.iy1 - 128
	var f := CURB
	var office := b.building(x0, y0, x1, y1, {"name": "cube farm", "floor": f, "ceil": f + 256, "floorTex": "OFCCARP1", "ceilTex": "OFCCEIL1", "wallTex": "OFCCUB01", "facade": "CONC_5", "roofTex": "CONC_3", "light": 0.98, "lightColor": "#f4f8ff"},
		[{"side": "s", "at": (x0 + x1) / 2, "w": 128, "tex": "EYEDOOR0"}, {"side": "n", "at": (x0 + x1) / 2, "w": 128, "tex": "EYEDOOR0"}, {"side": "w", "at": (y0 + y1) / 2, "tex": "DR1_01"}], k.walk)
	var x := x0 + 192
	while x + 128 < x1 - 128:
		if absf(x + 64 - (x0 + x1) / 2) >= 200:
			b.panel(x, y0 - WALL_T - 12, 128, f + 96, 128, "OP_WIND2"); b.panel(x, y1 + WALL_T, 128, f + 96, 128, "OP_WIND2")
		x += 384
	var cw := 256.0
	var ch := 224.0
	var aisle := 160.0
	var cxk := x0 + 256
	while cxk + 2 * cw < x1 - 256:
		var cyk := y0 + 320
		while cyk + ch < y1 - 320:
			if absf(cyk + ch / 2 - (y0 + y1) / 2) >= 160:
				for pf in [[cxk, 1], [cxk + cw, -1]]:
					var px: float = pf[0]
					var face: int = pf[1]
					b.prop(px, cyk, px + cw, cyk + 8, f, f + 112, "OFCCUB01", "OFCCUB03")
					b.prop(px if face > 0 else px + cw - 8, cyk, px + 8 if face > 0 else px + cw, cyk + ch, f, f + 112, "OFCCUB01", "OFCCUB03")
					var dx := px + cw / 2
					b.prop(dx - 80, cyk + 16, dx + 80, cyk + 72, f, f + 36, "OFCCUB03", "OFCDESK2" if face > 0 else "OFCDESK1")
			cyk += ch + 96
		cxk += 2 * cw + aisle
	b.panel(x1 - 12 - 256, y1 - 12, 256, f + 64, 128, "MONITOR")
	b.panel(x0 + 12, y1 - 12, 256, f + 64, 128, "TERMPAN1")
	b.scatter(B.in_blocks([office]), B.items(["SHOPPER", 1]), 4, 140, 0.1, {"name": "office staff"})
	b.scatter(B.in_rect(k.ix0 + 16, k.iy0 + 16, k.ix1 - 16, k.iy0 + 112), B.items(["PLANT:bush_small_1", 1, "PLANT:bush_small_2", 1]), 20, 90, 0.2, {"name": "office planting"})

# ---- 3,0 THE PLAZA
static func _plaza(b: B, k: Dictionary) -> void:
	var plaza := b.sector(B.box(k.ix0, k.iy0, k.ix1, k.iy1), {"name": "plaza", "floor": CURB, "floorTex": "CONC_1", "lowerTex": "CONC_4", "wallTex": "CONC_4", "light": 0.84})
	var cx: float = (k.ix0 + k.ix1) / 2.0
	for n in 5:
		var x: float = k.ix0 + 256 + n * 512
		b.sector(B.box(x, k.iy0 + 256, x + 320, k.iy0 + 576), {"name": "inlay", "floor": CURB, "floorTex": "DIAG_1" if n == 2 else ("CONC_5" if n % 2 else "XTX_1"), "lowerTex": "CONC_4", "light": 0.84})
		b.sector(B.box(x, k.iy0 + 832, x + 320, k.iy0 + 1152), {"name": "paving", "floor": CURB, "floorTex": "XTX_1", "lowerTex": "CONC_4", "light": 0.84})
	var sx0 := cx - 768
	var sx1 := cx + 768
	var sy0: float = k.iy1 - 1024
	var sy1: float = k.iy1 - 256
	b.sector(B.box(sx0 - 96, sy0 - 96, sx1 + 96, sy1 + 64), {"name": "stage step", "floor": CURB + 20, "floorTex": "CONC_3", "lowerTex": "CAUTSTR2", "wallTex": "CAUTSTR2", "light": 0.82})
	b.sector(B.box(sx0, sy0, sx1, sy1), {"name": "stage", "floor": CURB + 40, "floorTex": "XTX_1", "lowerTex": "CONC_4", "wallTex": "CONC_4", "light": 0.86})
	b.prop(cx - 480, sy1 - 64, cx + 480, sy1 - 16, CURB + 40, CURB + 40 + 384, "CONC_5", "CONC_5")
	b.prop(cx - 423, sy1 - 72, cx + 423, sy1 - 64, CURB + 112, CURB + 112 + 240, "TESTPA00", "CONC_5")
	for px in [cx - 560, cx + 496]:
		b.prop(px, sy1 - 80, px + 64, sy1 - 16, CURB + 40, CURB + 40 + 448, "CONC_7", "CONC_3")
	b.panel(cx - 480 - 256 - 32, sy1 - 28, 256, CURB + 120, 128, "MONITOR"); b.panel(cx + 480 + 32, sy1 - 28, 256, CURB + 120, 128, "MONITOR")
	b.sign(k.ix0 + 192, k.iy0 + 700, k.ix0 + 192 + 625, k.iy0 + 724, "GZDOOM", CURB, "s", {"name": "badge", "floorTex": "CONC_1"})
	b.scatter(B.in_blocks([plaza]), B.items(["TOWNIE", 2, "SHOPPER", 2]), 7, 120, 0.5, {"name": "audience"})

# ---- 0,1 THE CEMETERY
static func _cemetery(b: B, k: Dictionary) -> void:
	var gx0: float = k.ix0 + 64
	var gy0: float = k.iy0 + 64
	var gx1: float = k.ix1 - 64
	var gy1: float = k.iy1 - 64
	var MIST := {"color": "#9aa890", "density": 18}
	var gates := [{"side": "s", "at": (gx0 + gx1) / 2, "w": 192}, {"side": "e", "at": (gy0 + gy1) / 2, "w": 192}]
	var pts := []
	var gaps := []
	var run_g := func(from: Vector2, to: Vector2, side: String, horiz: bool) -> void:
		pts.append(from)
		var forward := to.x > from.x if horiz else to.y > from.y
		for g in gates:
			if g.side != side:
				continue
			var lo: float = g.at - g.w / 2.0
			var hi: float = g.at + g.w / 2.0
			var a2 := lo if forward else hi
			var b2 := hi if forward else lo
			var P := Vector2(a2, from.y) if horiz else Vector2(from.x, a2)
			var Q := Vector2(b2, from.y) if horiz else Vector2(from.x, b2)
			pts.append_array([P, Q])
			gaps.append([P, Q])
	run_g.call(Vector2(gx0, gy0), Vector2(gx1, gy0), "s", true); run_g.call(Vector2(gx1, gy0), Vector2(gx1, gy1), "e", false)
	run_g.call(Vector2(gx1, gy1), Vector2(gx0, gy1), "n", true); run_g.call(Vector2(gx0, gy1), Vector2(gx0, gy0), "w", false)
	var yard := b.sector(pts, {"name": "cemetery", "floor": CURB, "floorTex": "MOSS_01", "lowerTex": "DIRT_02", "wallTex": "IVY1", "light": 0.62, "fog": MIST.duplicate()})
	var gap_keys := {}
	for g in gaps:
		gap_keys[DocCompile._line_key(b.v(g[0].x, g[0].y), b.v(g[1].x, g[1].y))] = true
	for e in B.edges(pts):
		if not gap_keys.has(DocCompile._line_key(b.v(e[0].x, e[0].y), b.v(e[1].x, e[1].y))):
			b.line(e[0], e[1], {"midTex": "RAILING", "blocking": true})
	b.sector(B.box((gx0 + gx1) / 2 - 64, gy0 + 1, (gx0 + gx1) / 2 + 64, gy1 - 900), {"name": "path", "floor": CURB, "floorTex": "DIRT_01", "lowerTex": "DIRT_02", "light": 0.62, "fog": MIST.duplicate()})
	for r in 9:
		for c in 16:
			if b.rnd() < 0.18:
				continue
			var x := gx0 + 256 + c * 150 + (b.rnd() - 0.5) * 30
			var y := gy0 + 320 + r * 240 + (b.rnd() - 0.5) * 20
			if absf(x - (gx0 + gx1) / 2) < 140:
				continue
			if x > gx1 - 900 and y > gy1 - 900:
				continue
			var vr := 0 if b.rnd() < 0.55 else 1 + int(b.rnd() * 7)
			b.thing("GRAVESTONE", x, y, {"angle": -PI / 2 + (b.rnd() - 0.5) * 0.2, "variant": vr})
	var mx0 := gx1 - 800
	var my0 := gy1 - 800
	var mx1 := gx1 - 256
	var my1 := gy1 - 256
	b.building(mx0, my0, mx1, my1, {"name": "mausoleum", "floor": CURB + 16, "ceil": CURB + 16 + 256, "floorTex": "CONC_4", "ceilTex": "CONC_5", "wallTex": "CONC_7", "facade": "CONC_7", "roofTex": "CONC_3", "doorFloor": "CONC_4", "light": 0.35},
		[{"side": "s", "at": (mx0 + mx1) / 2, "tex": "EYEDOORC"}], yard)
	b.sector(B.box(mx0 - 64, my0 - 64, mx1 + 64, my0), {"name": "mausoleum step", "floor": CURB + 16, "floorTex": "CONC_4", "lowerTex": "CONC_4", "light": 0.5, "fog": MIST.duplicate()})
	for xy in [[gx0 + 96, gy0 + 96], [gx1 - 96, gy0 + 96], [gx0 + 96, gy1 - 96], [gx1 - 96, gy1 - 96], [gx0 + 96, (gy0 + gy1) / 2], [(gx0 + gx1) / 2 - 300, gy1 - 96], [(gx0 + gx1) / 2 + 300, gy1 - 96]]:
		b.plant(b.pick(FIRS), xy[0], xy[1])
	b.scatter(B.in_blocks([yard]), B.items(["TOWNIE", 1]), 0.6, 160, 0.2, {"name": "mourners"})
	b.scatter(B.in_blocks([yard]), B.items(["PLANT:grass", 3, "PLANT:fern", 2]), 18, 60, 0.7, {"name": "long grass"})

# ---- 1,1 THE OPS CENTRE
static func _ops(b: B, k: Dictionary) -> void:
	var x0: float = k.ix0 + 192
	var y0: float = k.iy0 + 192
	var x1: float = k.ix1 - 192
	var y1: float = k.iy1 - 192
	var f := CURB + 16
	var apron := b.sector(B.box(k.ix0 + 64, k.iy0 + 64, k.ix1 - 64, k.iy1 - 64), {"name": "ops apron", "floor": CURB, "floorTex": "CONC_3", "lowerTex": "CAUTSTR2", "wallTex": "CAUTSTR2", "light": 0.8})
	var ops := b.building(x0, y0, x1, y1, {"name": "ops centre", "floor": f, "ceil": f + 256, "floorTex": "METALP1", "ceilTex": "OP_BLNK2", "wallTex": "OPBLANK", "facade": "METALP1", "roofTex": "METALP1", "doorFloor": "CAUTSTR2", "light": 0.82, "lightColor": "#dde8ff"},
		[{"side": "s", "at": (x0 + x1) / 2, "w": 128, "tex": "EYEDOOR0"}, {"side": "w", "at": (y0 + y1) / 2, "tex": "DR1_01"}, {"side": "e", "at": (y0 + y1) / 2, "tex": "EYEDORC0"}], apron)
	var panels := ["DEVPAN1A", "TERMPAN1", "DEVPAN2A", "OP_VENT2", "OPSILENT", "OP_WIND2", "DEVPAN1A", "OP_BLNK3", "DEVPAN2A", "OP_BLNK2", "REDLIGHT", "TERMPAN1"]
	var n := panels.size()
	var kk := 0
	var x := x0 + 128
	while x + 128 <= x1 - 128:
		if absf(x + 64 - (x0 + x1) / 2) < 160:
			kk += 1
			x += 160
			continue
		b.panel(x, y1 - 24, 128, f + 64, 128, panels[kk % n]); kk += 1
		b.panel(x, y0 + 12, 128, f + 64, 128, panels[(kk + 5) % n])
		x += 160
	var y := y0 + 256
	while y + 128 <= y1 - 256:
		if absf(y + 64 - (y0 + y1) / 2) >= 160:
			b.panel(x1 - 24, y, 128, f + 64, 128, panels[kk % n], "y"); kk += 1
			b.panel(x0 + 12, y, 128, f + 64, 128, panels[(kk + 3) % n], "y")
		y += 160
	for r in 3:
		var yy := y0 + 480 + r * 448
		for a in [x0 + 384, x1 - 384 - 768]:
			for m in 3:
				var mx: float = a + m * 272
				b.prop(mx, yy, mx + 256, yy + 128, f, f + 40, "OPBLANK", "KEYBOARD")
				b.prop(mx, yy + 128, mx + 256, yy + 144, f + 40, f + 168, "MONITOR", "OP_BLNK3")
	var rx0 := (x0 + x1) / 2 - 320
	var rx1 := (x0 + x1) / 2 + 320
	var ry0 := (y0 + y1) / 2 + 160
	var ry1 := ry0 + 640
	b.sector(B.box(rx0, ry0, rx1, ry1), {"name": "reactor", "floor": f - 16, "floorTex": "CAUTSTR2", "lowerTex": "CAUTSTR2", "light": 0.7})
	var rc := Vector2((rx0 + rx1) / 2, (ry0 + ry1) / 2)
	b.prop(rc.x - 96, rc.y - 96, rc.x + 96, rc.y + 96, f - 16, f + 256, "REACTB00", "REDLIGHT")
	for e in [[rx0 + 16, ry0 + 16], [rx1 - 80, ry0 + 16], [rx0 + 16, ry1 - 80], [rx1 - 80, ry1 - 80]]:
		b.prop(e[0], e[1], e[0] + 64, e[1] + 64, f - 16, f + 112, "EYEDORC0", "REDLIGHT")
	b.scatter(B.in_blocks([ops]), B.items(["SHOPPER", 1]), 2, 200, 0.1, {"name": "operators"})

# ---- 2,1 THE MANSION, round a courtyard
static func _mansion(b: B, k: Dictionary) -> void:
	var x0: float = k.ix0 + 256
	var y0: float = k.iy0 + 256
	var x1: float = k.ix1 - 256
	var y1: float = k.iy1 - 256
	var f := CURB + 24
	b.sector(B.box(k.ix0 + 64, k.iy0 + 64, k.ix1 - 64, k.iy1 - 64), {"name": "mansion lawn", "floor": CURB, "floorTex": "LAWN2", "lowerTex": "CONC_5", "wallTex": "CONC_5", "light": 0.84})
	var terrace := b.sector(B.box(x0 - 96, y0 - 96, x1 + 96, y1 + 96), {"name": "mansion terrace", "floor": CURB + 16, "floorTex": "XTX_1", "lowerTex": "CONC_5", "wallTex": "CONC_5", "light": 0.82})
	var cx0 := x0 + 704
	var cy0 := y0 + 704
	var cx1 := x1 - 704
	var cy1 := y1 - 704
	var house := b.building(x0, y0, x1, y1, {"name": "mansion", "floor": f, "ceil": f + 256, "floorTex": "OFCCARP1", "ceilTex": "MANINT1", "wallTex": "MANINT1", "facade": "CONC_1", "roofTex": "CONC_3", "doorFloor": "XTX_1", "light": 0.9, "lightColor": "#ffd8a8",
		"hole": [cx0 - WALL_T, cy0 - WALL_T, cx1 + WALL_T, cy1 + WALL_T]},
		[{"side": "s", "at": (x0 + x1) / 2, "w": 128, "tex": "DR1_01"}, {"side": "e", "at": (y0 + y1) / 2, "tex": "DR1_01"}], terrace)
	var x := x0 + 160
	while x + 128 < x1 - 128:
		if absf(x + 64 - (x0 + x1) / 2) >= 200:
			b.panel(x, y0 - WALL_T - 12, 128, f + 80, 128, "OP_WIND2"); b.panel(x, y1 + WALL_T, 128, f + 80, 128, "OP_WIND2")
		x += 320
	var court := b.building(cx0, cy0, cx1, cy1, {"name": "courtyard", "outdoor": true, "floor": f, "ceil": f + 1024, "floorTex": "XTX_1", "ceilTex": "SKY", "wallTex": "CONC_1", "facade": "MANINT1", "roofTex": "CONC_3", "doorFloor": "XTX_1", "light": 0.86},
		[{"side": "s", "at": (cx0 + cx1) / 2, "w": 128, "h": 192}, {"side": "n", "at": (cx0 + cx1) / 2, "w": 128, "h": 192}, {"side": "e", "at": (cy0 + cy1) / 2, "w": 128, "h": 192}, {"side": "w", "at": (cy0 + cy1) / 2, "w": 128, "h": 192}], house)
	var mx := (cx0 + cx1) / 2
	var my := (cy0 + cy1) / 2
	b.sector(B.octagon(mx, my, 208), {"name": "fountain rim", "floor": f + 20, "floorTex": "CONC_5", "lowerTex": "CONC_5", "light": 0.86})
	b.sector(B.octagon(mx, my, 160), {"name": "fountain", "floor": f + 4, "floorTex": "WAT201", "lowerTex": "CONC_5", "light": 0.86})
	for p in [[cx0 + 128, cy0 + 128], [cx1 - 128, cy0 + 128], [cx0 + 128, cy1 - 128], [cx1 - 128, cy1 - 128]]:
		b.plant("bush_large_2", p[0], p[1])
	x = x0 + 256
	while x < x1 - 128:
		for y in [y0 + 352, y1 - 352]:
			if absf(x - (x0 + x1) / 2) >= 200:
				b.prop(x - 24, y - 24, x + 24, y + 24, f, f + 256, "CONC_7", "CONC_7")
		x += 384
	b.scatter(B.in_blocks([house]), B.items(["TOWNIE", 1]), 1.2, 220, 0.3, {"name": "guests"})
	b.scatter(B.in_blocks([court]), B.items(["PLANT:fern", 2, "PLANT:bush_small_1", 1]), 10, 70, 0.6, {"name": "courtyard beds"})

# ---- 3,1 THE MARKET SQUARE
static func _market(b: B, k: Dictionary) -> void:
	var sq := b.sector(B.box(k.ix0, k.iy0, k.ix1, k.iy1), {"name": "market square", "floor": CURB, "floorTex": "CONC_2", "lowerTex": "CONC_4", "wallTex": "CONC_4", "light": 0.84})
	var cx: float = (k.ix0 + k.ix1) / 2.0
	var cy: float = (k.iy0 + k.iy1) / 2.0
	for r in 4:
		for c in 5:
			if (r == 1 or r == 2) and c == 2:
				continue
			var x: float = k.ix0 + 320 + c * 512
			var y: float = k.iy0 + 384 + r * 640
			b.prop(x, y, x + 256, y + 128, CURB, CURB + 40, "MANINT1", "OFCDESK2")
			b.prop(x, y + 112, x + 16, y + 128, CURB, CURB + 128, "METALP1", "METALP1")
			b.prop(x + 240, y + 112, x + 256, y + 128, CURB, CURB + 128, "METALP1", "METALP1")
			b.prop(x - 16, y + 64, x + 272, y + 144, CURB + 128, CURB + 144, "OFCCUB03", "OFCCUB01")
			if c < 4:
				b.plant(b.pick(STREET), x + 384, y + 64)
	b.sector(B.box(cx - 320, cy - 320, cx + 320, cy + 320), {"name": "pavilion floor", "floor": CURB + 16, "floorTex": "XTX_1", "lowerTex": "CONC_4", "light": 0.84})
	for p in [[cx - 256, cy - 256], [cx + 208, cy - 256], [cx - 256, cy + 208], [cx + 208, cy + 208]]:
		b.prop(p[0], p[1], p[0] + 48, p[1] + 48, CURB + 16, CURB + 16 + 240, "CONC_7", "CONC_7")
	b.prop(cx - 300, cy - 300, cx + 300, cy + 300, CURB + 256, CURB + 288, "CONC_5", "CONC_3")
	b.scatter(B.in_blocks([sq]), B.items(["TOWNIE", 3, "SHOPPER", 2]), 10, 110, 0.5, {"name": "market crowd"})

# ---- 0,2 THE WOOD
static func _wood(b: B, k: Dictionary) -> void:
	var WF := {"color": "#6a7a58", "density": 22}
	var wood := b.sector(B.box(k.ix0, k.iy0, k.ix1, k.iy1), {"name": "the wood", "floor": CURB, "floorTex": "GRASS1", "lowerTex": "DIRT_02", "wallTex": "DIRT_02", "light": 0.64, "fog": WF.duplicate()})
	var mid: float = (k.iy0 + k.iy1) / 2.0
	b.sector(B.box(k.ix0 + 64, mid - 80, k.ix1 - 64, mid + 80), {"name": "track", "floor": CURB, "floorTex": "DIRT_01", "lowerTex": "DIRT_02", "light": 0.72, "fog": WF.duplicate()})
	var ox: float = k.ix0 + 2100
	var oy: float = k.iy0 + 2200
	b.sector(B.octagon(ox, oy, 300), {"name": "clearing", "floor": CURB, "floorTex": "MOSS_01", "lowerTex": "ROCK_01", "light": 0.82, "fog": WF.duplicate()})
	b.sector(B.octagon(ox, oy, 150, 7), {"name": "outcrop", "floor": CURB + 20, "floorTex": "MOSS_01", "lowerTex": "ROCK_01", "wallTex": "ROCK_01", "light": 0.9, "fog": WF.duplicate()})
	b.sector(B.octagon(ox + 20, oy - 10, 80, 5), {"name": "outcrop top", "floor": CURB + 40, "floorTex": "MOSS_01", "lowerTex": "ROCK_01", "wallTex": "ROCK_01", "light": 0.9, "fog": WF.duplicate()})
	b.scatter(B.in_blocks([wood]), B.items(["PLANT:fir_tall_1", 22, "PLANT:fir_tall_2", 22, "PLANT:fir_medium", 16, "PLANT:fir_young", 14,
		"PLANT:bush_large_1", 8, "PLANT:bush_small_1", 6]), 75, 48, 0.4, {"name": "firs", "scaleMin": 0.9, "scaleMax": 1.25})
	b.scatter(B.in_blocks([wood]), B.items(["PLANT:grass", 5, "PLANT:fern", 4, "PLANT:bush_small_2", 1]), 50, 30, 0.6, {"name": "undergrowth"})

# ---- 1,2 THE QUARRY
static func _quarry(b: B, k: Dictionary) -> void:
	b.sector(B.box(k.ix0, k.iy0, k.ix1, k.iy1), {"name": "quarry floor", "floor": CURB, "floorTex": "DIRT3", "lowerTex": "ROCK_01", "wallTex": "ROCK_01", "light": 0.8})
	var px0: float = k.ix0 + 96
	var py0: float = k.iy0 + 96
	var px1: float = k.ix1 - 96
	var py1: float = k.iy0 + 1500
	b.sector(B.box(k.ix1 - 520, k.iy0 + 1540, k.ix1 - 120, k.iy0 + 1740), {"name": "spoil", "floor": CURB, "floorTex": "DIRT2", "lowerTex": "ROCK_01", "light": 0.8})
	var FLOORS := ["DIRT3", "DIRT_01", "ROCK_01", "DIRT_02", "ROCK_01", "DIRT_01", "ROCK_01", "DIRT_02"]
	var z := CURB
	for n in 8:
		z -= 24
		var inset := n * 64
		b.sector(B.box(px0 + inset, py0 + inset, px1 - inset, py1 - inset), {"name": "bench %d" % (n + 1), "floor": z, "floorTex": FLOORS[n],
			"lowerTex": "ROCK_01", "wallTex": "ROCK_01", "light": 0.78 - n * 0.02})
	b.sector(B.box(px0 + 8 * 64, py0 + 8 * 64, px1 - 8 * 64, py1 - 8 * 64), {"name": "quarry pool", "floor": z - 20, "floorTex": "WAT201", "lowerTex": "ROCK_01", "light": 0.62})
	var mx0: float = k.ix0 + 96
	var my0: float = k.iy0 + 1800
	var mx1: float = k.ix1 - 96
	var my1: float = k.iy1 - 96
	var t1 := CURB + 384
	var t2 := t1 + 256
	var nx0 := (mx0 + mx1) / 2 - 96
	var nx1 := (mx0 + mx1) / 2 + 96
	var ny1 := my0 + 192
	var lower := [Vector2(mx0, my0), Vector2(nx0, my0), Vector2(nx0, ny1), Vector2(nx1, ny1), Vector2(nx1, my0), Vector2(mx1, my0), Vector2(mx1, my1), Vector2(mx0, my1)]
	b.sector(lower, {"name": "crag", "floor": t1, "floorTex": "MOSS_01", "lowerTex": "CLIFF2A", "wallTex": "CLIFF2A", "light": 0.84})
	b.line(Vector2(nx0, my0), Vector2(nx0, ny1), {"tex": "WFALLA1"}); b.line(Vector2(nx0, ny1), Vector2(nx1, ny1), {"tex": "WFALLA1"}); b.line(Vector2(nx1, ny1), Vector2(nx1, my0), {"tex": "WFALLA1"})
	b.line(Vector2(mx1, my0), Vector2(mx1, my1), {"tex": "LWNCLIF2"}); b.line(Vector2(mx1, my1), Vector2(mx0, my1), {"tex": "CLIFF1"}); b.line(Vector2(mx0, my1), Vector2(mx0, my0), {"tex": "LWNCLIF1"})
	b.sector(B.box(nx0, my0, nx1, ny1), {"name": "plunge pool", "floor": CURB - 16, "floorTex": "WAT201", "lowerTex": "ROCK_01", "light": 0.7})
	var ux0 := mx0 + 320
	var uy0 := my0 + 512
	var ux1 := mx1 - 320
	var uy1 := my1 - 192
	b.sector([Vector2(ux0, uy0), Vector2(nx0, uy0), Vector2(nx1, uy0), Vector2(ux1, uy0), Vector2(ux1, uy1), Vector2(ux0, uy1)],
		{"name": "upper crag", "floor": t2, "floorTex": "MOSS_01", "lowerTex": "CLIFF2C", "wallTex": "CLIFF2C", "light": 0.86})
	b.line(Vector2(nx0, uy0), Vector2(nx1, uy0), {"tex": "WFALLA1"})
	b.line(Vector2(ux1, uy0), Vector2(ux1, uy1), {"tex": "CLIFF2B"}); b.line(Vector2(ux0, uy1), Vector2(ux0, uy0), {"tex": "CLIFF2B"})
	b.sector(B.box(nx0 - 64, ny1 + 32, nx1 + 64, uy0 - 32), {"name": "upper pool", "floor": t1 - 12, "floorTex": "WAT201", "lowerTex": "ROCK_01", "light": 0.72})
	b.scatter(B.in_rect(mx0 + 64, my0 + 64, mx1 - 64, my1 - 64), B.items(["PLANT:fir_young", 2, "PLANT:fir_medium", 1, "PLANT:bush_small_1", 2, "PLANT:grass", 4]), 16, 70, 0.5, {"name": "on the crag"})

# ---- 2,2 THE BRUTALIST HALL
static func _hall(b: B, k: Dictionary) -> void:
	var x0: float = k.ix0 + 128
	var y0: float = k.iy0 + 128
	var x1: float = k.ix1 - 128
	var y1: float = k.iy1 - 128
	var f := CURB
	var mx := (x0 + x1) / 2
	var my := (y0 + y1) / 2
	var hall := b.building(x0, y0, x1, y1, {"name": "brutalist hall", "floor": f, "ceil": f + 448, "floorTex": "CONC_4", "ceilTex": "CONC_5", "wallTex": "CONC_4", "facade": "CONC_7", "roofTex": "CONC_3", "doorH": 256, "doorFloor": "CONC_4", "light": 0.5,
		"fog": {"color": "#3c3a36", "density": 14}, "hole": [mx - 288 - WALL_T, my - 288 - WALL_T, mx + 288 + WALL_T, my + 288 + WALL_T]},
		[{"side": "s", "at": (x0 + x1) / 2, "w": 256}, {"side": "n", "at": (x0 + x1) / 2, "w": 256}, {"side": "e", "at": (y0 + y1) / 2, "w": 192}, {"side": "w", "at": (y0 + y1) / 2, "w": 192}], k.walk)
	for zz in [f + 272, f + 96]:
		var x := x0 + 192
		while x + 128 < x1 - 128:
			if absf(x + 64 - mx) >= 256:
				b.panel(x, y0 - WALL_T - 12, 128, zz, 128, "OP_WIND2"); b.panel(x, y1 + WALL_T, 128, zz, 128, "OP_WIND2")
			x += 256
		var y := y0 + 192
		while y + 128 < y1 - 128:
			if absf(y + 64 - my) >= 224:
				b.panel(x0 - WALL_T - 12, y, 128, zz, 128, "OP_WIND2", "y"); b.panel(x1 + WALL_T, y, 128, zz, 128, "OP_WIND2", "y")
			y += 256
	var x := x0 + 384
	while x < x1 - 256:
		var y := y0 + 384
		while y < y1 - 256:
			if not (absf(x - mx) < 320 and absf(y - my) < 320):
				b.sector(B.box(x - 48, y - 48, x + 48, y + 48), {"name": "pillar", "floor": f + 448, "floorTex": "CONC_7", "lowerTex": "CONC_7", "light": 0.5})
			y += 512
		x += 512
	b.building(mx - 288, my - 288, mx + 288, my + 288, {"name": "light well", "outdoor": true, "floor": f, "ceil": f + 448, "floorTex": "CONC_3", "ceilTex": "SKY", "wallTex": "CONC_4", "facade": "CONC_4", "roofTex": "CONC_3", "light": 0.8},
		[{"side": "s", "at": mx, "w": 384, "h": 384}, {"side": "n", "at": mx, "w": 384, "h": 384}, {"side": "e", "at": my, "w": 384, "h": 384}, {"side": "w", "at": my, "w": 384, "h": 384}], hall)
	b.sector(B.box(mx - 160, my - 160, mx + 160, my + 160), {"name": "pit", "outdoor": true, "floor": f - 24, "ceil": f + 448, "floorTex": "DIAG_2", "ceilTex": "SKY", "wallTex": "CONC_4", "lowerTex": "CAUTSTR2", "light": 0.7})
	b.scatter(B.in_blocks([hall]), B.items(["SHOPPER", 1, "TOWNIE", 1]), 1.5, 200, 0.3, {"name": "wanderers"})

# ---- 3,2 THE YARD
static func _yard(b: B, k: Dictionary) -> void:
	var yard := b.sector(B.box(k.ix0, k.iy0, k.ix1, k.iy1), {"name": "yard", "floor": CURB, "floorTex": "CONC_3", "lowerTex": "CONC_4", "wallTex": "CONC_4", "light": 0.76})
	var mx: float = (k.ix0 + k.ix1) / 2.0
	b.sector(B.box(mx - 96, k.iy0 + 128, mx + 96, k.iy1 - 640), {"name": "channel", "floor": CURB - 16, "floorTex": "WAT201", "lowerTex": "CONC_4", "wallTex": "CONC_4", "light": 0.74})
	for pp in [[k.ix0 + 128, mx - 256], [mx + 256, k.ix1 - 128]]:
		var px0: float = pp[0]
		var px1: float = pp[1]
		var y: float = k.iy0 + 192
		while y + 640 < k.iy1 - 640:
			b.sector(B.box(px0, y, px1, y + 640), {"name": "pad", "floor": CURB + 8, "floorTex": "METALP1", "lowerTex": "CAUTSTR2", "light": 0.78})
			var x := px0 + 64
			while x + 480 < px1:
				var h := 128 if b.rnd() < 0.5 else 256
				b.prop(x, y + 96, x + 480, y + 288, CURB + 8, CURB + 8 + h, b.pick(["METALP1", "OPBLANK", "OP_BLNK3"]), "METALP1")
				b.panel(x + 32, y + 84, 128, CURB + 8, 128, "DOOR0001"); b.panel(x + 320, y + 84, 128, CURB + 8, 128, "DOOR0001")
				if b.rnd() < 0.6:
					b.prop(x, y + 352, x + 480, y + 544, CURB + 8, CURB + 136, b.pick(["OPBLANK", "METALP1", "OP_BLNK2"]), "METALP1")
				x += 544
			y += 832
	var sx0: float = k.ix0 + 320
	var sy0: float = k.iy1 - 560
	var sx1: float = k.ix1 - 320
	var sy1: float = k.iy1 - 96
	b.building(sx0, sy0, sx1, sy1, {"name": "shed", "floor": CURB, "ceil": CURB + 256, "floorTex": "CAUTSTR2", "ceilTex": "METALP1", "wallTex": "METALP1", "facade": "METALP1", "roofTex": "METALP1", "doorH": 128, "light": 0.6},
		[{"side": "s", "at": sx0 + 512, "w": 128, "tex": "DOOR0001"}, {"side": "s", "at": sx1 - 512, "w": 128}], yard)
	b.scatter(B.in_blocks([yard]), B.items(["TOWNIE", 1]), 1, 260, 0.2, {"name": "hands"})

# ---- 0,3 THE MEADOW
static func _meadow(b: B, k: Dictionary) -> void:
	var m := b.sector(B.box(k.ix0, k.iy0, k.ix1, k.iy1), {"name": "meadow", "floor": CURB, "floorTex": "GRASS5", "lowerTex": "DIRT_01", "wallTex": "DIRT_01", "light": 0.86})
	for q in [[400, 500, 900, 700, "GRASS6"], [1500, 2300, 800, 400, "GRASS6"], [600, 1900, 700, 600, "LAWN1"], [1900, 300, 600, 500, "DIRT3"]]:
		b.sector(B.box(k.ix0 + q[0], k.iy0 + q[1], k.ix0 + q[0] + q[2], k.iy0 + q[1] + q[3]), {"name": "meadow patch", "floor": CURB, "floorTex": q[4], "lowerTex": "DIRT_01", "light": 0.86})
	for o in [[k.ix0 + 500, k.iy0 + 1500, 150], [k.ix0 + 2550, k.iy0 + 1150, 120], [k.ix0 + 2600, k.iy0 + 2300, 170], [k.ix0 + 900, k.iy0 + 350, 110]]:
		b.sector(B.octagon(o[0], o[1], o[2], 7), {"name": "outcrop", "floor": CURB + 20, "floorTex": "MOSS_01", "lowerTex": "ROCK_01", "light": 0.92})
		b.sector(B.octagon(o[0] + 10, o[1] - 10, o[2] * 0.55, 6), {"name": "outcrop top", "floor": CURB + 40, "floorTex": "ROCK_01", "lowerTex": "ROCK_01", "light": 0.92})
	var scx: float = k.ix0 + 1900
	var scy: float = k.iy0 + 1350
	b.sector(B.octagon(scx, scy, 420, 12), {"name": "stone circle", "floor": CURB + 16, "floorTex": "LAWN1", "lowerTex": "DIRT_01", "light": 0.9})
	for n in 9:
		var a := n / 9.0 * PI * 2
		var x := scx + cos(a) * 300
		var y := scy + sin(a) * 300
		var hgt := 112 + (n % 3) * 40
		b.prop(x - 24, y - 16, x + 24, y + 16, CURB + 16, CURB + 16 + hgt, "CONC_7", "MOSS_01")
	b.prop(scx - 64, scy - 32, scx + 64, scy + 32, CURB + 16, CURB + 56, "ROCK_01", "MOSS_01")
	b.scatter(B.in_blocks([m]), B.items(["TOWNIE", 1]), 0.8, 300, 0.2, {"name": "walkers"})
	b.scatter(B.in_blocks([m]), B.items(["PLANT:fir_tall_2", 1, "PLANT:street_broad", 1, "PLANT:street_big", 1, "PLANT:bush_large_1", 3, "PLANT:bush_large_2", 2]), 5, 180, 0.6, {"name": "copses"})
	b.scatter(B.in_blocks([m]), B.items(["PLANT:grass", 6, "PLANT:fern", 2, "PLANT:bush_small_1", 1]), 40, 36, 0.5, {"name": "meadow grass"})

# ---- 1,3 THE TEST CHAMBER
static func _lab(b: B, k: Dictionary) -> void:
	var x0: float = k.ix0 + 256
	var y0: float = k.iy0 + 256
	var x1: float = k.ix1 - 256
	var y1: float = k.iy1 - 256
	var f := CURB
	b.sector(B.box(k.ix0 + 64, k.iy0 + 64, k.ix1 - 64, k.iy1 - 64), {"name": "test apron", "floor": CURB, "floorTex": "64TEST", "lowerTex": "64TEST", "wallTex": "64TEST", "light": 0.82})
	var lab := b.building(x0, y0, x1, y1, {"name": "test chamber", "floor": f, "ceil": f + 384, "floorTex": "256TEST", "ceilTex": "512TEST", "wallTex": "128TEST", "facade": "128TEST", "roofTex": "512TEST", "doorFloor": "64TEST", "light": 1.0},
		[{"side": "s", "at": (x0 + x1) / 2, "w": 192}], k.walk)
	var n := [0]
	var dbg := func() -> String:
		var s := "DEBUG%03d" % n[0]
		n[0] += 1
		return s
	var x := x0 + 192
	while x + 128 < x1 - 128 and n[0] < 16:
		b.panel(x, y1 - 24, 128, f + 96, 128, dbg.call())
		x += 224
	var y := y0 + 256
	while y + 128 < y1 - 128 and n[0] < 16:
		b.panel(x1 - 24, y, 128, f + 96, 128, dbg.call(), "y")
		y += 224
	x = x1 - 320
	while x > x0 + 128 and n[0] < 16:
		if absf(x + 64 - (x0 + x1) / 2) >= 256:
			b.panel(x, y0 + 12, 128, f + 96, 128, dbg.call())
		x -= 224
	b.panel(x0 + 12, y0 + 512, 128, f + 96, 128, "SQUIRREL", "y")
	b.panel(x0 + 12, y0 + 768, 128, f + 96, 128, "OFCCUB02", "y")
	b.panel(x0 + 12, y0 + 960, 423, f + 64, 240, "TESTPA00", "y")
	b.panel(x0 + 12, y0 + 1500, 625, f + 96, 300, "GZDOOM", "y")
	b.panel(x0 + 320, y1 - 24, 1024, f + 240, 144, "CLOUDS02")
	b.panel(x1 - 24, y0 + 512, 512, f + 240, 144, "CLOUDS01", "y")
	var T := ["64TEST", "128TEST", "256TEST", "512TEST"]
	for i in T.size():
		var s := 64 << i
		var tx := x0 + 320 + i * 520
		var ty := (y0 + y1) / 2 - s / 2.0
		b.prop(tx, ty, tx + s, ty + s, f, f + s, T[i], T[i])
	var X := ["XTX_5", "XTX_6", "XTX_7", "XTX_8"]
	for i in X.size():
		b.prop(x0 + 320 + i * 320, y1 - 640, x0 + 448 + i * 320, y1 - 512, f, f + 128, X[i], X[i])
	b.scatter(B.in_blocks([lab]), B.items(["SHOPPER", 1]), 1, 260, 0.1, {"name": "testers"})

# ---- 2,3 THE LAKE
static func _lake(b: B, k: Dictionary) -> void:
	var LF := {"color": "#a8b8b0", "density": 6}
	var shore := b.sector(B.box(k.ix0, k.iy0, k.ix1, k.iy1), {"name": "shore", "floor": CURB, "floorTex": "DIRT3", "lowerTex": "ROCK_01", "wallTex": "ROCK_01", "light": 0.86})
	var lx0: float = k.ix0 + 320
	var ly0: float = k.iy0 + 320
	var lx1: float = k.ix1 - 320
	var ly1: float = k.iy1 - 320
	var cx := (lx0 + lx1) / 2
	var cy := (ly0 + ly1) / 2
	var rx := (lx1 - lx0) / 2
	var ry := (ly1 - ly0) / 2
	var ring := func(dr: float, n: int) -> Array:
		var out := []
		for q in n:
			out.append(Vector2(B.jr(cx + (rx - dr) * cos(q * 2 * PI / n)), B.jr(cy + (ry - dr) * sin(q * 2 * PI / n))))
		return out
	b.sector(ring.call(0, 16), {"name": "beach", "floor": CURB - 8, "floorTex": "DIRT_01", "lowerTex": "ROCK_01", "light": 0.84, "fog": LF.duplicate()})
	b.sector(ring.call(96, 16), {"name": "shallows", "floor": -12, "floorTex": "WAT201", "lowerTex": "ROCK_01", "light": 0.62, "fog": LF.duplicate()})
	b.sector(ring.call(352, 16), {"name": "lake", "floor": -36, "floorTex": "WAT201", "lowerTex": "ROCK_01", "light": 0.56, "fog": LF.duplicate()})
	for isl in [[cx - 350, cy + 200, 180], [cx + 320, cy - 240, 140]]:
		var ix: float = isl[0]
		var iy: float = isl[1]
		var r: float = isl[2]
		b.sector(B.octagon(ix, iy, r, 10, 0), {"name": "island", "floor": -12, "floorTex": "DIRT_01", "lowerTex": "ROCK_01", "light": 0.86, "fog": LF.duplicate()})
		b.sector(B.octagon(ix, iy, r - 40, 10, 0), {"name": "island grass", "floor": CURB, "floorTex": "GRASS5", "lowerTex": "DIRT_02", "light": 0.9, "fog": LF.duplicate()})
		b.plant(b.pick(FIRS), ix, iy, 1.1)
		b.plant("bush_small_1", ix + r * 0.4, iy - r * 0.3)
		b.plant("bush_large_1", ix - r * 0.35, iy + r * 0.2)
	b.sector(B.box(cx - 48, ly0 + 110, cx + 48, ly0 + 330), {"name": "jetty", "floor": CURB, "floorTex": "OFCDESK2", "lowerTex": "MANINT1", "light": 0.86, "fog": LF.duplicate()})
	b.scatter(B.in_rect(k.ix0 + 32, k.iy0 + 32, k.ix1 - 32, k.iy0 + 280), B.items(["TOWNIE", 1]), 5, 150, 0.4, {"name": "bathers"})
	b.scatter(B.in_blocks([shore]), B.items(["PLANT:fir_medium", 2, "PLANT:fir_tall_1", 1, "PLANT:street_round", 1, "PLANT:bush_small_2", 2]), 6, 110, 0.5, {"name": "shore trees"})

# ---- 3,3 THE RUINS
static func _ruins(b: B, k: Dictionary) -> void:
	var RF := {"color": "#8c8878", "density": 8}
	var r := b.sector(B.box(k.ix0, k.iy0, k.ix1, k.iy1), {"name": "ruins", "floor": CURB, "floorTex": "MOSS_01", "lowerTex": "CONC_7", "wallTex": "CONC_7", "light": 0.66, "fog": RF.duplicate()})
	for sh in [[256, 256, 896, 704], [1408, 384, 1024, 896], [384, 1408, 1152, 1024], [1792, 1664, 768, 832]]:
		var x0: float = k.ix0 + sh[0]
		var y0: float = k.iy0 + sh[1]
		var x1: float = x0 + sh[2]
		var y1: float = y0 + sh[3]
		var th := 32.0
		b.sector(B.box(x0 + th, y0 + th, x1 - th, y1 - th), {"name": "shell floor", "floor": CURB, "floorTex": b.pick(["CONC_5", "DIRT1", "MOSS_01"]), "lowerTex": "CONC_7", "light": 0.66, "fog": RF.duplicate()})
		var TEX := ["CONC_7", "CONC_5", "CONC_4"]
		var run := func(ax: float, ay: float, bx: float, by: float, horiz: bool) -> void:
			var ln := bx - ax if horiz else by - ay
			var hgt := 96 + b.rnd() * 160
			var tex: String = b.pick(TEX)
			var s := 0.0
			while s < ln:
				var piece := 64 + B.jr(b.rnd() * 3) * 64
				var e := minf(ln, s + piece)
				hgt = maxf(24, minf(288, hgt + (b.rnd() - 0.55) * 96))
				if b.rnd() < 0.18:
					var rx: float = ax + s + 16 if horiz else ax + (-40.0 if b.rnd() < 0.5 else th + 8)
					var ry: float = ay + (-40.0 if b.rnd() < 0.5 else th + 8) if horiz else ay + s + 16
					var rx1 := rx + 32 + b.rnd() * 24
					b.prop(rx, ry, rx1, ry + 32, CURB, CURB + 12 + B.jr(b.rnd() * 16), tex, "MOSS_01")
				else:
					var T: String = "IVY1" if b.rnd() < 0.25 else tex
					if horiz:
						b.prop(ax + s, ay, ax + e, ay + th, CURB, CURB + B.jr(hgt), T, "MOSS_01")
					else:
						b.prop(ax, ay + s, ax + th, ay + e, CURB, CURB + B.jr(hgt), T, "MOSS_01")
				s = e
		run.call(x0, y0, x1, y0, true); run.call(x0, y1 - th, x1, y1 - th, true)
		run.call(x0, y0 + th, x0, y1 - th, false); run.call(x1 - th, y0 + th, x1 - th, y1 - th, false)
	for n in 10:
		var gx: float = k.ix0 + 300 + b.rnd() * 2200
		var gy: float = k.iy0 + 2600 + b.rnd() * 200
		var ang := -PI / 2 + (b.rnd() - 0.5)
		b.thing("GRAVESTONE", gx, gy, {"angle": ang, "variant": int(b.rnd() * 8)})
	b.scatter(B.in_blocks([r]), B.items(["PLANT:fern", 4, "PLANT:grass", 3, "PLANT:bush_small_2", 1, "PLANT:fir_young", 1]), 30, 44, 0.65, {"name": "overgrowth"})

# ---- 0,3 AGAIN: THE BIOME BEDS down the meadow's west edge
const BEDS := [
	["SAND1", ["desert_big_cactus_1", "desert_cactus_5", "desert_cactus_6"],
		["desert_small_cactus_1", "desert_creosote_bush_5", "desert_bush_1", "desert_small_cactus_2"]],
	["WASTE1", ["wasteland_tree", "wasteland_tree_big_2", "wasteland_tree_big_3"],
		["desert_dead_creosote_bush_5", "wasteland_bush_1", "desert_dead_creosote_bush_6"]],
	["MOLTEN1", ["wasteland_small_tree_1", "wasteland_tree_small_2"], []],
	["SAVANNA1", ["savanna_tree_1"], ["savanna_grass_short_1", "savanna_grass_tall_1", "savanna_grass_short_2", "savanna_grass_tall_2", "desert_creosote_bush_6", "desert_bush_2"]],
	["FARMLND1", [], ["farm_wheat_1", "farm_wheat_2", "farm_wheat_3", "farm_wheat_4", "farm_wheat_2", "farm_wheat_1", "farm_wheat_4", "farm_wheat_3"]],
	["TUNDRA1", [], ["tundra_bush_1", "tundra_bush_2", "tundra_bush_3", "tundra_bush_4", "tundra_bush_5"]],
	["FROZEN1", ["pine_juvenile_fir_tree_1", "pine_juvenile_fir_tree_2", "pine_juvenile_fir_tree_4"], []],
	["ARCTIC1", ["pine_fir_tree_4", "pine_barrens_tree"], []],
	["PINEBAR1", ["pine_fir_tree_1", "pine_fir_tree_2", "pine_fir_tree_3"],
		["pine_fern_1", "pine_forest_bush_1", "pine_fern_2", "pine_forest_bush_2", "pine_fern_3", "pine_forest_bush_3", "pine_fern_4"]],
	["MEADOW1", ["new_meadow_tree_1"], ["new_meadow_bush_1", "new_meadow_bush_2", "new_meadow_bush_3", "new_meadow_bush_4"]],
	["MEADOW2", ["new_meadow_tree_2"], ["new_meadow_flower_1", "new_meadow_grass_1", "new_meadow_flower_2", "new_meadow_grass_2"]],
	["MEADOW3", ["new_meadow_tree_3"], ["new_meadow_fern_1", "new_meadow_fern_2", "new_meadow_grass_tall_1", "new_meadow_fern_3", "new_meadow_fern_4"]],
	["MEADOW4", [], ["new_meadow_flower_1", "new_meadow_grass_tall_1", "new_meadow_flower_2", "new_meadow_grass_1"]],
	["MEADOW5", [], ["new_meadow_grass_2", "new_meadow_bush_2", "new_meadow_grass_1"]],
	["GRASCHK1", ["meadow_tree_big", "meadow_tree_medium"], ["meadow_bush_var_a", "meadow_grass_var_a", "meadow_bush_var_b"]],
	["GRASCHK2", ["meadow_tree_really_big"], ["meadow_grass_var_b", "meadow_grass_var_a", "meadow_grass_var_b"]],
	["CANDY1", [], []], ["CITYCON1", [], []], ["CITYMET1", [], []], ["CITYMET2", [], []], ["CITYSKRT", [], []],
]

static func _beds(b: B, k: Dictionary) -> void:
	for n in BEDS.size():
		var tex: String = BEDS[n][0]
		var trees: Array = BEDS[n][1]
		var low: Array = BEDS[n][2]
		var x0: float = k.ix0 + 48
		var y0: float = k.iy0 + 48 + n * 128
		b.sector(B.box(x0, y0, x0 + 256, y0 + 112), {"name": "biome bed", "floor": CURB + 8, "floorTex": tex, "lowerTex": tex, "light": 0.86})
		for i in trees.size():
			b.plant(trees[i], x0 + 32 + i * 96, y0 + 40)
		for i in low.size():
			b.plant(low[i], x0 + 16 + (i + 0.5) * (224.0 / low.size()), y0 + 88)
