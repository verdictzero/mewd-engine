## MEWD — fire (js/fire.js: FireSystem).
##
## The store burning down is the game. Everything else — the zombies, the
## weapons, the layout — exists to make burning it down interesting. So
## the fire is not an effect painted over the level, it is a simulation
## running underneath it, and the level is built out of things that feed
## it.
##
## A GRID OF FUEL. Thirty-two units to a cell, laid over the whole map.
## Each cell knows how much there is to burn there, taken from the sector
## it sits in — a shelf of stock is worth a great deal, bare lino almost
## nothing, and the car park nothing at all. Fire spreads between
## neighbouring cells, consumes the fuel, and leaves the cell dead.
##
## WHAT MAKES IT A GAME AND NOT A SCREENSAVER is that the fuel is laid
## out the way a supermarket is: dense in the aisles, dense in the
## stockroom, and THIN in the walkways between them. So a fire in one
## aisle will happily eat that aisle and then stop at the cross-aisle,
## and burning the place down means deliberately carrying fire across the
## gaps.
##
## WHAT FIRE CAN CROSS. A one-sided line is a wall and stops it dead. A
## two-sided line is a gap in something, and fire goes through gaps —
## under a shelf, over a counter, through a doorway. The only two-sided
## line that stops it is one whose opening has closed, which is to say a
## shut door. Worked out once at startup and stored as four bits a cell,
## because doing it per spread would be thousands of segment
## intersections a second.
##
## HEAT RISES AND FALLS. A cell that catches does not go instantly to
## maximum; it builds, peaks, and dies back as its fuel runs out. That
## curve is why a fire has a visible FRONT — a bright edge advancing into
## fresh stock with a dimming trail of embers behind it — instead of
## being a uniformly glowing region that grows.
##
## The simulation is pure — a fuel grid and some integers — and is drawn
## by FireSprites (godot/scripts/render/fire_sprites.gd), which reads it.
##
## NOTE ON THE PACKED ARRAYS: GDScript's packed arrays are copy-on-write
## values, so every write here goes through the member itself. A local
## alias of one (`var h := heat`) followed by a write to either copies
## the whole grid — per write.
class_name FireSystem
extends RefCounted

const CELL := 32

# ------------------------------------------------------------------
# The shape of one cell's life
#
# Heat runs 0..255. A cell that catches climbs toward a peak, holds
# while it has fuel, and dies back to nothing once the fuel is gone.
#
# NO FIRE SURVIVES ITSELF, and that is the requirement now. It is a
# statement about percolation rather than about flammability. A fire
# crossing a region carries on only if each burning cell lights, on
# average, MORE THAN ONE new one before it burns out:
#
#   expected spreads  =  tics alight  x  chance  x  neighbours
#
# Above one, the fire runs away and takes everything connected to it,
# and no player is required. Below one it peters out. It used to be above
# one everywhere — one match took 85-94% of the shop with nobody in it —
# and then a fire the player has to WORK at was asked for. So every
# number below is under the line: a match is a patch, a walkway is a
# wall, and the shelves are the fuse. The car park is fuel 0, no
# burning, ever: the safe room and the way out.
# ------------------------------------------------------------------

## How often the simulation steps, in game tics — the pace control, and
## deliberately separate from every other number here: the expected-
## spreads figure is counted in FIRE tics, so this buys pace and nothing
## else. It has been 2, 6, 18 and 3; it is 10 BECAUSE MUCH SLOWER WAS
## ASKED FOR THREE TIMES IN ONE SENTENCE. The other half of that request —
## that a fire should go OUT — is SPREAD_RICH.
const FIRE_INTERVAL := 10

const IGNITE_AT := 55      # heat a cell starts at when it catches
const PEAK := 255
const RISE := 14           # heat gained per fire tic while fuelled
const FALL := 9            # heat lost per fire tic once the fuel is gone
const SPREAD_AT := 80      # heat below which a cell cannot light another

## Fraction of a cell's ORIGINAL fuel consumed per fire tic at full heat.
## A fraction rather than a flat rate gives every cell a roughly similar
## LIFETIME however rich it is; and thin fuel is slower still, so bare
## floor smoulders for minutes and gets nowhere — a fire lying on the
## lino, visibly alight, visibly not going anywhere. Floats for this
## reason: as integers nothing under one unit a tic could be expressed.
const BURN_FRAC := 0.022

## What is left afterwards: a low glow that sits there before going
## cold, so the ground you have taken stays visibly taken. In FIRE tics.
const EMBER_HEAT := 20
const EMBER_TICS := 150

## How much of a region has to go before its surfaces are swapped for
## charred ones. Past about half it should read as a shop that HAS burnt.
const CHAR_AT := 0.5

## And how much before it is not a room any more. CHARRED IS A SURFACE
## AND GUTTED IS A STRUCTURE: holes through the walls, a slab with ash on
## it, and NO ROOF. 0.92 rather than 1.0 because a region's last few cells
## can be ones a wall keeps the fire out of.
const GUT_AT := 0.92

# ------------------------------------------------------------------
# AND WHAT IS STILL HOLDING IT UP
#
# CHARRED IS A SURFACE, GUTTED IS A STRUCTURE, AND COLLAPSED IS NEITHER.
# Steel does not care how much has burnt; it cares how LONG it has been
# hot, so INTEGRITY is a clock: one when the frame is whole, zero when it
# is on the floor, and falling for as long as there is fire AT the region
# — its own cells AND every region it is LINKED to, so what cooks the
# steel over aisle six is the fire in aisle five. A clock adds nothing to
# the world, which is why this is not a re-fuelling of the ruin (that
# made a fire that could not be stopped).
# ------------------------------------------------------------------

## Integrity lost per fire step by a ruin that is properly alight.
const COOK := 0.006
## How many cells alight count as a full fire, as an absolute.
const COOK_FULL := 6
## And how many times on the way down the roof is redrawn.
const WEAR_STEPS := 4

## Chance out of SPREAD_DEN, per fire tic, per direction, that a burning
## cell lights its neighbour; scales with the NEIGHBOUR's richness — fire
## moves toward what will take it.
const SPREAD_DEN := 65536
## The chance a cell of the RICHEST stock passes the fire on — the one
## number that decides whether this game has a fire in it or a fire
## problem.
const SPREAD_RICH := 400
## How fast the chance falls away as the fuel thins: at 2.4 a gondola is
## sixty times more willing to pass fire on than the bare floor.
const SPREAD_CURVE := 2.4

## Fire goes UP much more readily than it goes along (a staircase is a
## chimney with a handrail), and through a party wall far less readily.
const UP_SPREAD := 4.0
const CEIL_SPREAD := 0.4
const PARTY_SPREAD := 0.10

## How hard the rain works on a cell it can reach, and how much of a
## cell's chance to light a wet neighbour it takes away.
const RAIN_COOL := 22
const RAIN_SPREAD := 0.85

static var _spread_table := PackedInt32Array()

static func _build_spread_table() -> void:
	if not _spread_table.is_empty():
		return
	_spread_table.resize(1024)
	for f in 1024:
		_spread_table[f] = 0 if f <= 0 else mini(SPREAD_RICH, roundi(SPREAD_RICH * pow(f / 300.0, SPREAD_CURVE)))

static func spread_chance(f: float) -> int:
	return _spread_table[clampi(int(f), 0, 1023)]

## ONE ROLL IN 65536, out of two eight-bit rolls: bare lino wants to pass
## the fire on about nine times in sixty-five thousand, which a smaller
## denominator cannot express.
static func spread_roll(n: float) -> bool:
	return float((U.p_random() << 8) | U.p_random()) < n

static func burn_frac(f0: float) -> float:
	return BURN_FRAC * (1.0 if f0 >= 280.0 else 0.22 + 0.78 * (f0 / 280.0))

## How hot a cell can get, from how much there is to burn. Thin fuel
## smoulders below a hundred and thirty; a full gondola goes to white.
static func peak_heat(f0: float) -> float:
	return maxf(112.0, minf(PEAK, 112.0 + f0 * 0.5))

## The wind as four multipliers, east, north, west, south, on the chance
## of a cell lighting the one in that direction. Units per tic in.
static func wind_multipliers(wx: float, wy: float) -> PackedFloat32Array:
	var m := func(v: float) -> float: return maxf(0.4, minf(1.8, 1.0 + v * 0.75))
	return PackedFloat32Array([m.call(wx), m.call(wy), m.call(-wx), m.call(-wy)])

var game
## THE WHOLE SIMULATION, ON A SWITCH, at the user's request: a world
## whose map says `noCellFire` has nothing that spreads. The grid is still
## allocated, so everything that asks it hears "no fire anywhere".
var off := false
var origin_x := 0.0
var origin_y := 0.0
var cols := 0
var rows := 0
## one grid per storey level, stacked; plane 0 is the ground everywhere
var levels := 1
var plane := 0

var fuel := PackedFloat32Array()
var fuel0 := PackedFloat32Array()
var heat := PackedByteArray()
var ember := PackedInt32Array()
var link := PackedByteArray()        # 1 E, 2 N, 4 W, 8 S, 16 up
var party := PackedByteArray()
var sector_of := PackedInt32Array()
## UNDER THE SKY: the car park, the road, the wood. What the rain falls on.
var open := PackedByteArray()
## where fire can climb: cell -> [cell, mul, cell, mul, ...]
var up := {}

## WHICH CELLS CHANGED, so the picture of this grid a shader reads (the
## JS burn grid) does not have to be looked for — level 0 only.
var grid_dirty := PackedInt32Array()
var grid_dirty_all := true

var active := PackedInt32Array()     # cells currently alight
var _active_set := PackedByteArray()
var total_fuel := 0.0
var burnt_fuel := 0.0
var hot_cells := 0
var tics := 0

## the weather, as the fire feels it (js/weather.js climate.wind/.rain);
## the clear night's (js/weather.js WEATHERS.clear.wind) and dry, until a
## weather port sets them
var wind := Vector2(0.28, 0.05)
var rain := 0.0

# per-region progress, so a region can be charred when it has gone
var sector_fuel := PackedFloat64Array()
var sector_burnt := PackedFloat64Array()
var sector_cells := PackedInt32Array()
## The stages, per region. The JS keeps these on the sector object
## (`charred`, `gutted`, `collapsed`, `integrity`, `wearStep`); here they
## are the fire's, and char_of() is how the renderer asks.
var charred := PackedByteArray()
var gutted := PackedByteArray()
var collapsed := PackedByteArray()
var integrity := PackedFloat64Array()
var wear_step := PackedInt32Array()
## AND WHICH REGIONS ARE A BUILDING AT ALL: something to burn and a
## ceiling that is not the sky, read ONCE at build time because gutting
## sets the sky on every region whose deck has gone.
var structural := PackedByteArray()
var newly_charred := PackedInt32Array()
var newly_gutted := PackedInt32Array()
var newly_collapsed := PackedInt32Array()
var newly_sagged := PackedInt32Array()
var _standing: Array[int] = []
var _cook_hot := PackedInt32Array()

## The one fire light, parked in the middle of whatever is burning
## nearest the player (js/material.js world.fireLight*). Map coordinates.
var fire_light_pos := Vector3.ZERO
var fire_light := 0.0
var fire_light_range := 420.0

## apply_char's debounce, as js/game.js keeps it
var _geo_dirty := false
var _geo_at := 0
var _dirty_sectors := {}

func _init(g) -> void:
	_build_spread_table()
	game = g
	var lv: Level = g.level
	off = bool(lv.world.get("noCellFire", false))
	var fb: Rect2 = lv.fire_bounds
	origin_x = floorf(fb.position.x / CELL) * CELL - CELL
	origin_y = floorf(fb.position.y / CELL) * CELL - CELL
	cols = ceili((fb.end.x - origin_x) / CELL) + 2
	rows = ceili((fb.end.y - origin_y) / CELL) + 2
	# AS MANY PLANES AS THERE IS FUEL TO PUT IN THEM: a roof storey is a
	# shell and gets none
	levels = 1
	for s in lv.sectors:
		if _fuel_of(s) > 0 and _storey_of(s) + 1 > levels:
			levels = _storey_of(s) + 1
	plane = cols * rows
	var n := plane * levels
	fuel.resize(n)
	fuel0.resize(n)
	heat.resize(n)
	ember.resize(n)
	link.resize(n)
	party.resize(n)
	sector_of.resize(n)
	sector_of.fill(-1)
	open.resize(n)
	_active_set.resize(n)
	var ns := lv.sectors.size()
	sector_fuel.resize(ns)
	sector_burnt.resize(ns)
	sector_cells.resize(ns)
	charred.resize(ns)
	gutted.resize(ns)
	collapsed.resize(ns)
	integrity.resize(ns)
	wear_step.resize(ns)
	structural.resize(ns)
	_cook_hot.resize(ns)
	# EVERY REGION STARTS WHOLE
	for s in lv.sectors:
		integrity[s.index] = float(s.props.get("integrity", 1.0))
	_seed()
	for s in lv.sectors:
		structural[s.index] = 1 if (sector_fuel[s.index] > 0.0 and s.ceil_tex != "SKY") else 0
	_link_cells()

# ------------------------------------------------------------------
# The sector's fire properties, off its document (Level.Sector.props)
# ------------------------------------------------------------------

static func _fuel_of(s: Level.Sector) -> int:
	return int(s.props.get("fuel", 0))

static func _storey_of(s: Level.Sector) -> int:
	return int(s.props.get("__storey", 0))

static func _is_open(s: Level.Sector) -> bool:
	return s.outdoor or bool(s.props.get("forest", false)) or bool(s.props.get("outside", false))

func idx(cx: int, cy: int, lv := 0) -> int:
	return lv * plane + cy * cols + cx

func cell_x(x: float) -> int:
	return clampi(floori((x - origin_x) / CELL), 0, cols - 1)

func cell_y(y: float) -> int:
	return clampi(floori((y - origin_y) / CELL), 0, rows - 1)

func world_x(cx: int) -> float:
	return origin_x + cx * CELL + CELL / 2.0

func world_y(cy: int) -> float:
	return origin_y + cy * CELL + CELL / 2.0

## Every cell takes its fuel from the sector it lands in. A sector with
## fuel 0 will never burn, and that is how the map author draws
## firebreaks. RASTERISED, NOT QUERIED: each sector fills its own
## bounding box once, first one wins — the same answer sector_at gives.
func _seed() -> void:
	if off:
		return
	var lv: Level = game.level
	for s in lv.sectors:
		var b := s.bbox
		var cx0 := cell_x(b.position.x)
		var cx1 := cell_x(b.end.x)
		var cy0 := cell_y(b.position.y)
		var cy1 := cell_y(b.end.y)
		var op := 1 if _is_open(s) else 0
		var f := _fuel_of(s)
		var lvl := _storey_of(s)
		if lvl >= levels:
			continue      # a storey with no fuel anywhere
		# AND NO CELL FOR A STOREY THAT CANNOT BURN: plane 0 is seeded
		# whatever its fuel, because the grid has to know where the
		# firebreaks are
		if lvl > 0 and f <= 0:
			continue
		var rect := s.is_rect
		for cy in range(cy0, cy1 + 1):
			var wy := world_y(cy)
			var in_row := rect and wy > b.position.y and wy < b.end.y
			for cx in range(cx0, cx1 + 1):
				var i := idx(cx, cy, lvl)
				if sector_of[i] >= 0:
					continue
				var wx := world_x(cx)
				if not (in_row and wx > b.position.x and wx < b.end.x) and not U.point_in_poly(s.poly, wx, wy):
					continue
				sector_of[i] = s.index
				sector_cells[s.index] += 1
				if op:
					open[i] = 1
				if f <= 0:
					continue
				# a little variation, so the burn front is ragged rather
				# than an expanding rectangle
				var v := maxf(1.0, roundf(f * (0.75 + (U.p_random() / 255.0) * 0.5)))
				fuel[i] = v
				fuel0[i] = v
				total_fuel += v
				sector_fuel[s.index] += v

const _DIRS := [[1, 0, 1, 4], [0, 1, 2, 8], [-1, 0, 4, 1], [0, -1, 8, 2]]
const _UPS := [[0, 0], [1, 0], [0, 1], [-1, 0], [0, -1]]

func _link_cells() -> void:
	if off:
		return
	var lv: Level = game.level
	for lvl in levels:
		for cy in rows:
			for cx in cols:
				var i := idx(cx, cy, lvl)
				var si := sector_of[i]
				if si < 0:
					continue
				var x1 := world_x(cx)
				var y1 := world_y(cy)
				var A: Level.Sector = lv.sectors[si]
				# up: the cell overhead and the four beside it, wherever the
				# two storeys share any air at all — indoors only
				if lvl + 1 < levels and not open[i]:
					var ups := []
					for d in _UPS:
						var nx: int = cx + d[0]
						var ny: int = cy + d[1]
						if nx < 0 or ny < 0 or nx >= cols or ny >= rows:
							continue
						var j := idx(nx, ny, lvl + 1)
						var sj := sector_of[j]
						if sj < 0:
							continue
						var B: Level.Sector = lv.sectors[sj]
						var share := minf(A.ceil, B.ceil) - maxf(A.floor, B.floor)
						var side: bool = d[0] != 0 or d[1] != 0
						if share > 0.0:
							# THE STAIRWELL: the wall asked at the height they share
							var zm := (maxf(A.floor, B.floor) + minf(A.ceil, B.ceil)) / 2.0
							if side and _fire_blocked(x1, y1, world_x(nx), world_y(ny), zm):
								continue
							ups.append_array([j, UP_SPREAD])
							continue
						# AND THE CEILING, which is the slow way: straight up,
						# same cell, through the deck
						if side:
							continue
						if B.floor - A.ceil > 24.0:
							continue
						if _fuel_of(A) == 0 or _fuel_of(B) == 0:
							continue
						ups.append_array([j, CEIL_SPREAD])
					if not ups.is_empty():
						up[i] = ups
						link[i] |= 16
				for d in _DIRS:
					var nx: int = cx + d[0]
					var ny: int = cy + d[1]
					if nx < 0 or ny < 0 or nx >= cols or ny >= rows:
						continue
					var j := idx(nx, ny, lvl)
					var sj := sector_of[j]
					if sj < 0:
						continue
					var bit: int = d[2]
					# TWO CELLS OF ONE CONVEX REGION ARE ALWAYS LINKED — a wall
					# in this map is the GAP between two regions — as long as
					# both centres are STRICTLY inside it
					if sj == si and A.convex:
						var bb := A.bbox
						var nxw := world_x(nx)
						var nyw := world_y(ny)
						if x1 > bb.position.x + 0.5 and x1 < bb.end.x - 0.5 and y1 > bb.position.y + 0.5 and y1 < bb.end.y - 0.5 \
								and nxw > bb.position.x + 0.5 and nxw < bb.end.x - 0.5 and nyw > bb.position.y + 0.5 and nyw < bb.end.y - 0.5:
							link[i] |= bit
							continue
					var zi := A.floor + 8.0
					if not _fire_blocked(x1, y1, world_x(nx), world_y(ny), zi):
						link[i] |= bit
						continue
					# blocked — unless it is a party wall, which fire gets
					# through eventually: a terrace rather than eight fires
					if A.props.get("party", false) and lv.sectors[sj].props.get("party", false):
						party[i] |= bit

## Walls stop fire. Gaps do not — a shut door is the only two-sided line
## that counts as a wall here, and a door is judged on what it WILL be
## (dynamic: open), since these links are worked out once at startup.
##
## AT A HEIGHT, because a map in storeys has rooms over rooms: the wall
## between two first floors is not the wall between the two rooms under
## them, so each side's storey at z is asked (span_in); a column of one
## hands back the sector it was given, and this is the check it was.
func _fire_blocked(x1: float, y1: float, x2: float, y2: float, z := 8.0) -> bool:
	var lv: Level = game.level
	for l in lv.lines_in_box(minf(x1, x2), minf(y1, y2), maxf(x1, x2), maxf(y1, y2)):
		var t := U.seg_intersect(x1, y1, x2, y2, l.x1, l.y1, l.x2, l.y2)
		if t < 0.0:
			continue
		if l.front == -1 or l.back == -1:
			return true
		var a: Level.Sector = lv.sectors[l.front]
		var b: Level.Sector = lv.sectors[l.back]
		if l.multi:
			a = lv.span_in(a, z)
			b = lv.span_in(b, z)
			# a building's outside wall in the openings at this height
			if l.blocking and not l.mid_z.is_empty() and Level._in_mid_z(l, z):
				return true
		if a.props.get("dynamic", false) or b.props.get("dynamic", false):
			continue
		if minf(a.ceil, b.ceil) - maxf(a.floor, b.floor) <= 0.0:
			return true
	return false

# ------------------------------------------------------------------
# Setting things alight
# ------------------------------------------------------------------

## Put heat into the world at a point. `strength` is roughly how much
## fuel is being dumped there too — a fuel can makes its own. `radius`
## in map units; the box of cells it covers is lit. Returns how many
## cells caught.
##
## `z`, where it is known, is the height it happens at: on a map in
## storeys the fire goes into the PLANE of the storey there (plane_at),
## so a flamer on the terrace lights the terrace and not the yard under
## it; none of that is asked on a map of one storey.
func ignite(x: float, y: float, strength := 60.0, radius := float(CELL), z := NAN) -> int:
	# TODO(boxes): the JS hands the call to the grid world's boxes first
	# (this.boxes?.ignite) — not ported
	if off:
		return 0
	var pl := plane_at(x, y, z)
	if pl < 0:
		return 0
	var cx0 := cell_x(x - radius)
	var cx1 := cell_x(x + radius)
	var cy0 := cell_y(y - radius)
	var cy1 := cell_y(y + radius)
	var lit := 0
	for cy in range(cy0, cy1 + 1):
		for cx in range(cx0, cx1 + 1):
			var i := idx(cx, cy, pl)
			if sector_of[i] < 0:
				continue
			# ACCELERANT. Something poured here burns even on bare lino.
			# A flamethrower lays down about 40 — enough to burn where you
			# point it, never enough to spread; a bottle lays down over a
			# hundred, so its pool WILL reach into whatever is next to it.
			if strength > 40.0:
				var target := minf(150.0, roundf(strength * 0.62))
				if fuel[i] < target:
					var add := target - fuel[i]
					fuel[i] += add
					fuel0[i] += add
					total_fuel += add
					_touch(i)
			if fuel[i] <= 0.0:
				continue
			if heat[i] == 0:
				lit += 1
			heat[i] = maxi(heat[i], int(minf(peak_heat(fuel0[i]), IGNITE_AT + strength)))
			_activate(i)
	return lit

## The call a burning person makes as they go (js/actor.js burnTic, which
## calls fire.ignite(x, y, burnFuel, burnRadius)) — the same thing under
## the name the actor port asks for. `radius` is in map units, as the
## JS's burnRadius is: 1 is the cell they are standing in.
func add_heat(x: float, y: float, amount: float, radius := 1.0, z := NAN) -> int:
	return ignite(x, y, amount, float(radius), z)

## THE PLANE OF THE STOREY at (x, y, z) on a map in storeys: its storey
## in its column, or -1 where that storey has no cells (nothing to burn
## up there). Plane 0 with no height, and on every map of one storey.
func plane_at(x: float, y: float, z: float) -> int:
	if is_nan(z) or not game.level.layered:
		return 0
	var s: Level.Sector = game.level.span_at(x, y, z)
	if s == null:
		return 0
	return s.storey if s.storey < levels else -1

## AND PUTTING ONE OUT. Not symmetrical with ignite: fire is a THRESHOLD
## system, so taking heat away moves a cell across a line — under
## SPREAD_AT it stops recruiting, to nothing and it is out. WHAT IT
## CANNOT DO IS PUT THE FUEL BACK. Embers go too: a doused cell has its
## ember clock cleared, so the aisle behind you stays dark. ROUND, NOT
## SQUARE, unlike ignite — a spray is a cone. Returns cells cooled.
func douse(x: float, y: float, strength := 90.0, radius := float(CELL), z := NAN) -> int:
	if off:
		return 0
	var pl := plane_at(x, y, z)
	if pl < 0:
		return 0
	var cx0 := cell_x(x - radius)
	var cx1 := cell_x(x + radius)
	var cy0 := cell_y(y - radius)
	var cy1 := cell_y(y + radius)
	var r2 := radius * radius
	var cooled := 0
	for cy in range(cy0, cy1 + 1):
		for cx in range(cx0, cx1 + 1):
			var i := idx(cx, cy, pl)
			if sector_of[i] < 0 or heat[i] == 0:
				continue
			var dx := world_x(cx) - x
			var dy := world_y(cy) - y
			if dx * dx + dy * dy > r2:
				continue
			var fall := 1.0 - sqrt(dx * dx + dy * dy) / radius
			var take := roundi(strength * (0.35 + 0.65 * fall))
			var h: int = heat[i] - take
			cooled += 1
			if h <= EMBER_HEAT:
				heat[i] = 0
				ember[i] = 0
			else:
				heat[i] = h
	return cooled

## This cell's fuel moved, so the picture of the grid is out of date here.
func _touch(i: int) -> void:
	if i >= plane or grid_dirty_all:
		return
	if grid_dirty.size() > (1 << 16):
		grid_dirty_all = true
		grid_dirty.clear()
		return
	grid_dirty.append(i)

func _activate(i: int) -> void:
	if _active_set[i]:
		return
	_active_set[i] = 1
	active.append(i)

## How hot it is at (x, y), 0..1 — at height z, on a map in storeys.
func heat_at(x: float, y: float, z := NAN) -> float:
	var pl := plane_at(x, y, z)
	if pl < 0:
		return 0.0
	return heat[idx(cell_x(x), cell_y(y), pl)] / 255.0

func burn_fraction() -> float:
	return burnt_fuel / total_fuel if total_fuel > 0.0 else 0.0

## js/game.js burnPercent, which the HUD reads
func burn_percent() -> float:
	return burn_fraction() * 100.0

## What the status bar shows: cells actually alight, not the ember tail.
func burning_cells() -> int:
	return hot_cells

func live_cells() -> int:
	return active.size()

## How burnt a region looks: 1 gutted, 0.55 charred, 0 untouched
## (js/mapgeo.js charOf).
func char_of(si: int) -> float:
	if si < 0 or si >= charred.size():
		return 0.0
	return 1.0 if gutted[si] else (0.55 if charred[si] else 0.0)

# ------------------------------------------------------------------
# One step of the simulation
# ------------------------------------------------------------------

func tic() -> void:
	if off:
		return
	tics += 1
	if tics % FIRE_INTERVAL:
		return
	var next := PackedInt32Array()
	var to_ignite := PackedInt32Array()
	var hot := 0
	# THE WIND, as four multipliers — outside only; there is no wind in
	# aisle six. And THE RAIN, which only a cell under the sky feels.
	var wm := wind_multipliers(wind.x, wind.y)
	var sectors: Array = game.level.sectors
	for k in active.size():
		var i := active[k]
		var h := float(heat[i])
		var f := fuel[i]
		var si := sector_of[i]
		var wet := rain if (rain > 0.0 and rain_on(i)) else 0.0
		if f > 0.0:
			# burning: heat climbs toward what this much fuel can sustain,
			# and eats a fraction of the original per tic — so a rich cell
			# roars and a thin one smoulders, for about as long either way
			var f0 := fuel0[i]
			h = minf(peak_heat(f0), h + RISE)
			var eat := minf(f, f0 * burn_frac(f0) * (h / 255.0))
			fuel[i] = 0.0 if f - eat < 0.02 else f - eat
			_touch(i)
			burnt_fuel += eat
			if si >= 0:
				sector_burnt[si] += eat
				if sector_fuel[si] > 0.0:
					var gone := sector_burnt[si] / sector_fuel[si]
					if not charred[si] and gone >= CHAR_AT:
						charred[si] = 1
						newly_charred.append(si)
					if not gutted[si] and gone >= GUT_AT:
						gutted[si] = 1
						newly_gutted.append(si)
						if structural[si]:
							_standing.append(si)
			if fuel[i] <= 0.0:
				ember[i] = EMBER_TICS
			# RAIN ON A FIRE takes heat off faster than the fuel can put it
			# back — and out, with its fuel still in it
			if wet > 0.0:
				h -= roundf(RAIN_COOL * wet)
				if h <= 0.0:
					heat[i] = 0
					ember[i] = 0
					_active_set[i] = 0
					continue
		elif h > EMBER_HEAT:
			h -= FALL                                   # falling back to a glow
			if wet > 0.0:
				h -= roundf(RAIN_COOL * wet)
			if h < EMBER_HEAT:
				h = EMBER_HEAT
		elif ember[i] > 0 and wet > 0.0:
			ember[i] = 0
			heat[i] = 0
			_active_set[i] = 0
			continue
		elif ember[i] > 0:
			ember[i] -= 1                               # and sitting there a while
			h = 2.0 + roundf((EMBER_HEAT - 2) * float(ember[i]) / EMBER_TICS)
		else:
			heat[i] = 0
			_active_set[i] = 0
			continue
		heat[i] = int(h)
		if h >= SPREAD_AT:
			hot += 1
		# AND WHAT THE HEAT IS DOING TO THE STEEL: embers count
		if h > EMBER_HEAT:
			_credit_heat(i, si, link[i])
		# Spread. Only a well-established cell can light another, so a
		# fire has to take hold before it travels.
		if h >= SPREAD_AT:
			var lk := link[i]
			var windy := open[i] == 1
			if lk & 1:
				_try_spread(i + 1, to_ignite, wm[0] if windy else 1.0)
			if lk & 2:
				_try_spread(i + cols, to_ignite, wm[1] if windy else 1.0)
			if lk & 4:
				_try_spread(i - 1, to_ignite, wm[2] if windy else 1.0)
			if lk & 8:
				_try_spread(i - cols, to_ignite, wm[3] if windy else 1.0)
			# UP THE STAIRS, and readily
			if lk & 16:
				var ups: Array = up[i]
				for u in range(0, ups.size(), 2):
					_try_spread(ups[u], to_ignite, ups[u + 1])
			# and through the party wall, slowly
			var pw := party[i]
			if pw:
				if pw & 1:
					_try_spread(i + 1, to_ignite, PARTY_SPREAD)
				if pw & 2:
					_try_spread(i + cols, to_ignite, PARTY_SPREAD)
				if pw & 4:
					_try_spread(i - 1, to_ignite, PARTY_SPREAD)
				if pw & 8:
					_try_spread(i - cols, to_ignite, PARTY_SPREAD)
		next.append(i)
	active = next
	hot_cells = hot
	for j in to_ignite:
		if j < 0 or j >= heat.size():
			continue
		if fuel[j] <= 0.0 or heat[j] > 0:
			continue
		heat[j] = IGNITE_AT
		_activate(j)
	_cook_ruins()
	_burn_things()
	_update_atmosphere()

## Will the fire travel here, and how eagerly? About the NEIGHBOUR, not
## the cell doing the lighting. Nothing here is impossible; most of it is
## merely so unlikely that waiting is not a strategy.
func _try_spread(j: int, out: PackedInt32Array, mul := 1.0) -> void:
	if j < 0 or j >= heat.size():
		return
	var f := fuel[j]
	if f <= 0.0 or heat[j] > 0:
		return
	var chance := spread_chance(f) * mul
	# a wet cell is a hard cell to light
	if rain > 0.0 and rain_on(j):
		chance *= 1.0 - RAIN_SPREAD * rain
	if spread_roll(chance):
		out.append(j)

## Is the rain falling on this cell? Under the sky, or under a roof that
## has gone.
func rain_on(i: int) -> bool:
	if open[i]:
		return true
	var si := sector_of[i]
	return si >= 0 and gutted[si] == 1

# ------------------------------------------------------------------
# THE COLLAPSE CLOCK
# ------------------------------------------------------------------

func _cook_ruins() -> void:
	if _standing.is_empty():
		return
	var fell := false
	for si in _standing:
		var h := _cook_hot[si]
		_cook_hot[si] = 0
		if collapsed[si]:
			fell = true
			continue
		if h > 0:
			integrity[si] -= COOK * minf(1.0, float(h) / COOK_FULL)
		if integrity[si] <= 0.0:
			bring_down(si)
			fell = true
			continue
		var step := mini(WEAR_STEPS - 1, floori((1.0 - integrity[si]) * WEAR_STEPS))
		if step != wear_step[si]:
			wear_step[si] = step
			newly_sagged.append(si)
	if fell:
		_standing = _standing.filter(func(s: int) -> bool: return not collapsed[s])

## One hot cell, against every standing ruin it is cooking: its own
## region and the ones it is linked to, so heat reaches a neighbour
## exactly where flame could.
func _credit_heat(i: int, si: int, lk: int) -> void:
	if si >= 0 and gutted[si] and not collapsed[si]:
		_cook_hot[si] += 1
	if lk & 1:
		_credit_one(sector_of[i + 1], si)
	if lk & 2:
		_credit_one(sector_of[i + cols], si)
	if lk & 4:
		_credit_one(sector_of[i - 1], si)
	if lk & 8:
		_credit_one(sector_of[i - cols], si)

func _credit_one(j: int, si: int) -> void:
	if j >= 0 and j != si and gutted[j] and not collapsed[j]:
		_cook_hot[j] += 1

## Take a region down, from whatever state it was in. A bomb does not
## wait for the stages, but everything downstream is written against the
## flags, so a region blown flat passes through charred and gutted on its
## way, in one tic, in order.
func bring_down(si: int) -> bool:
	if collapsed[si] or not structural[si]:
		return false
	if not charred[si]:
		charred[si] = 1
		newly_charred.append(si)
	if not gutted[si]:
		gutted[si] = 1
		newly_gutted.append(si)
		_standing.append(si)
	integrity[si] = 0.0
	collapsed[si] = 1
	newly_collapsed.append(si)
	return true

## AND THE OTHER WAY TO BRING A BUILDING DOWN: a blast takes integrity
## off every region it reaches, falling off with distance, walked on the
## fire's own grid so it stops at the same walls. The nearest cell of a
## region decides how hard it was hit. Returns how many came down.
func damage_structure(x: float, y: float, radius: float, amount: float, lv := 0) -> int:
	if not (amount > 0.0) or not (radius > 0.0):
		return 0
	var seen := {}
	var cx0 := cell_x(x - radius)
	var cx1 := cell_x(x + radius)
	var cy0 := cell_y(y - radius)
	var cy1 := cell_y(y + radius)
	for cy in range(cy0, cy1 + 1):
		for cx in range(cx0, cx1 + 1):
			var dx := world_x(cx) - x
			var dy := world_y(cy) - y
			var d2 := dx * dx + dy * dy
			if d2 > radius * radius:
				continue
			var si := sector_of[idx(cx, cy, lv)]
			if si < 0 or not structural[si] or collapsed[si]:
				continue
			var bite := amount * (1.0 - sqrt(d2) / radius)
			if not seen.has(si) or seen[si] < bite:
				seen[si] = bite
	var down := 0
	for si in seen:
		integrity[si] -= seen[si]
		if integrity[si] <= 0.0 and bring_down(si):
			down += 1
	return down

# ------------------------------------------------------------------
# Burning things
# ------------------------------------------------------------------

## Anything standing in a hot cell catches, and anything alive in one
## gets hurt. Includes the player: there is no safe way to stand in a fire
## you started. Excludes the fireproof — the SWAT — who walk through it.
func _burn_things() -> void:
	for a in game.actors:
		if a.removed or a.fireproof or ("noclip" in a and a.noclip):
			continue
		var pa := plane_at(a.x, a.y, a.z)
		if pa < 0:
			continue
		var h := heat[idx(cell_x(a.x), cell_y(a.y), pa)]
		if h < 70:
			continue
		if a.flammable and not a.burning:
			a.ignite(280 + (U.p_random() & 127))
		elif a.shootable and not a.dead and (tics & 15) == 0:
			a.damage(3, null, {"fire": true})
	var p = game.player
	if p != null and not p.dead and p.has_method("damage"):
		var pp := plane_at(p.x, p.y, p.z)
		var h: int = heat[idx(cell_x(p.x), cell_y(p.y), pp)] if pp >= 0 else 0
		if h > 70 and (tics & 7) == 0:
			p.damage(maxi(2, h >> 5), null, {"fire": true})

## The one fire light parks itself in the middle of whatever is burning
## nearest the player. A sample, not a sum: with a whole aisle alight
## there can be hundreds of cells and the answer does not change.
##
## TODO(atmosphere): the JS also pulls the light toward the wood's fire,
## the flame leaving the gun and everybody on fire (forest/flame/fx
## glowInto), and hands the result to the world shader
## (world.fireLightPos/fireLight/fireLightRange). There is no fire light
## in world_light.gdshaderinc yet; these members are what it will read.
## The smoke and the ambient lift are js/weather.js's, off burn_fraction().
func _update_atmosphere() -> void:
	var p = game.player
	if p == null:
		return
	var sx := 0.0
	var sy := 0.0
	var sz := 0.0
	var sw := 0.0
	var step := maxi(1, active.size() >> 6)
	for k in range(0, active.size(), step):
		var i := active[k]
		var h := heat[i]
		if h < 60:
			continue
		var c := i % plane
		var x := world_x(c % cols)
		var y := world_y(c / cols)
		if U.dist2(x, y, p.x, p.y) > 900.0 * 900.0:
			continue
		var w := h / 255.0
		sx += x * w
		sy += y * w
		sw += w
		if sector_of[i] >= 0:
			sz += game.level.sectors[sector_of[i]].floor * w
	sx *= step
	sy *= step
	sw *= step
	if sw > 0.01:
		var s: Level.Sector = game.level.sector_at(sx / sw, sy / sw)
		var fz: float = (s.floor + 48.0) if s else 48.0
		if game.level.layered:
			fz = sz / (sw / step) + 48.0
		fire_light_pos = Vector3(sx / sw, sy / sw, fz)
		# flicker, keyed to the tic so it is the same for everything
		var flick := 0.86 + 0.14 * sin(tics * 0.7) * cos(tics * 0.31)
		fire_light = minf(1.8, sqrt(sw) * 0.36) * flick
		fire_light_range = 420.0 + minf(800.0, sw * 28.0)
	else:
		fire_light *= 0.86

# ------------------------------------------------------------------
# AND WHAT IT DOES TO THE BUILDING (js/game.js applyChar)
# ------------------------------------------------------------------

## Drain the stage lists, debounced as js/game.js does: half a dozen
## gondolas can pass a threshold in one second and each swap is a rebuild
## of the level's static geometry, so they are collected and the rebuild
## is due twenty tics after the last (thirty-five for a mere sag). Call
## once a tic, after tic(); returns the sector indices whose geometry is
## due a rebuild NOW, or an empty array.
##
## TODO(geometry): the JS swaps a charred region's textures for their
## charred twins (charredName), lifts its ambient to 0.58, jams sliding
## doors in it; a gutted one takes guttedSurfaces (ceiling to SKY, holed
## walls, ambient 0.66, its lamps removed); a collapsed one drops to the
## lowest standing neighbour plus collapsedSurfaces' floorRise (ambient
## 0.78); a sag re-hangs the ruin steel. All of that needs MapGeo to
## rebuild per block, which it cannot yet — the state is kept here, and
## char_of() is ready for the geometry to read.
func apply_char(game_tics: int) -> PackedInt32Array:
	for lst in [newly_charred, newly_gutted, newly_collapsed]:
		if not lst.is_empty():
			for si in lst:
				_dirty_sectors[si] = true
			_geo_dirty = true
			_geo_at = game_tics + 20
	newly_charred.clear()
	newly_gutted.clear()
	newly_collapsed.clear()
	if not newly_sagged.is_empty():
		for si in newly_sagged:
			_dirty_sectors[si] = true
		newly_sagged.clear()
		_geo_dirty = true
		_geo_at = maxi(_geo_at, game_tics + 35)
	if _geo_dirty and game_tics >= _geo_at:
		_geo_dirty = false
		var out := PackedInt32Array(_dirty_sectors.keys())
		_dirty_sectors.clear()
		return out
	return PackedInt32Array()
