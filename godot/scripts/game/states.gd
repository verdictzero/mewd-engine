## MEWD — state tables (js/states.js).
##
## Doom's monsters are a linked list of states: which sprite frame to
## show, for how many tics, one action to call the moment it starts, and
## which state comes next. That is the whole animation system and the
## whole AI scheduler — and why a Doom monster has weight: it cannot
## change its mind mid-frame, because the frame owns the next tics.
## Timing is in tics, 35 to the second. -1 tics rests for ever; a null
## next removes the actor.
class_name States

const TICRATE := 35

static var STATES := {}
static var ACTORS := {}
static var _built := false

## a person's drawing: 17 in a strip of 40x64 cells
const SHOPPERS := 17
const BLASTS := 26

## the troops: five views mirrored to eight for the turned frames, one
## drawing for the floor frames (js/people.js TROOPS)
const TROOPS := {
	"SWAT": {"sprite": "SWAT", "turn": "ABCDEFG", "flat": "HIJKLMNOPQRSTUVW", "views": 5, "strip": "swat"},
	"ARMY": {"sprite": "ARMY", "turn": "ABCDEFG", "flat": "HIJKLMNOPQRSTUVW", "views": 5, "strip": "army"},
}

static func _s(name: String, sprite: String, frame: String, tics: int, action, next, opts := {}) -> void:
	var st := {"name": name, "sprite": sprite, "frame": frame, "tics": tics, "action": action, "next": next, "fullbright": false}
	st.merge(opts, true)
	STATES[name] = st

static func state(name) -> Dictionary:
	build()
	if name == null:
		return {}
	return STATES.get(name, {})

static func actor(type: String) -> Dictionary:
	build()
	return ACTORS.get(type, {})

static func build() -> void:
	if _built:
		return
	_built = true
	# ---- THE SHOPPERS: one drawing held for ever; they sway, they run,
	# they burn, they freeze, they come apart
	_s("SHOP_STAND", "SHOP", "A", 8, "A_Watch", "SHOP_STAND2")
	_s("SHOP_STAND2", "SHOP", "A", 8, "A_Watch", "SHOP_STAND")
	_s("SHOP_RUN1", "SHOP", "A", 3, "A_Flee", "SHOP_RUN2")
	_s("SHOP_RUN2", "SHOP", "A", 3, "A_Flee", "SHOP_RUN1")
	_s("SHOP_BURN1", "SHOP", "A", 2, "A_Torch", "SHOP_BURN2", {"fullbright": true})
	_s("SHOP_BURN2", "SHOP", "A", 2, "A_Torch", "SHOP_BURN1", {"fullbright": true})
	_s("SHOP_GIB", "SHOP", "A", 1, "A_Gib", null)
	_s("SHOP_FROZE", "SHOP", "A", -1, null, "SHOP_FROZE")
	_s("SHOP_ASH1", "SHOP", "A", 4, "A_BurnAway", "SHOP_ASH2", {"fullbright": true})
	_s("SHOP_ASH2", "SHOP", "A", 4, "A_BurnAway", "SHOP_ASH1", {"fullbright": true})
	_s("SHOP_BORE", "SHOP", "A", -1, null, "SHOP_BORE")

	# ---- THE TROOPS: the Zombieman's table with the numbers looked at again
	_troop("SWAT", "SWAT", "A_SwatFire")
	_troop("ARMY", "ARMY", "A_ArmyFire")

	# ---- things that are not monsters
	_s("BLUD_REST", "BLUD", "A", -1, null, null)
	_s("GRAV_STAND", "GRV0", "A", -1, null, null)
	_s("ASH_REST", "ASH0", "A", -1, null, null)
	var letters := "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
	for i in BLASTS:
		_s("BLAST%d" % (i + 1), "BLST", letters[i], 1, null, null if i == BLASTS - 1 else "BLAST%d" % (i + 2), {"fullbright": true})
	_s("PUFF1", "PUFF", "A", 4, null, "PUFF2")
	_s("PUFF2", "PUFF", "B", 4, null, "PUFF3")
	_s("PUFF3", "PUFF", "C", 4, null, null)

	# ---- ACTOR TYPES, Doom's mobjinfo minus what nothing uses
	ACTORS["SHOPPER"] = {
		"name": "Shopper", "spawn": "SHOP_STAND", "see": "SHOP_RUN1", "death": "SHOP_GIB",
		"health": 12, "radius": 18, "height": 56, "mass": 100, "painchance": 0,
		"speed": 16, "monster": true, "flammable": true, "fuel": 90, "painSound": "shopper",
		"burn": "SHOP_BURN1", "burnTics": [3.5 * TICRATE, 7 * TICRATE],
		"freezable": true, "frozen": "SHOP_FROZE", "freezeReturn": "SHOP_RUN1",
		"burnAway": "SHOP_ASH1", "ashTics": [3.0 * TICRATE, 4.5 * TICRATE],
		"bored": "SHOP_BORE", "burnTrail": 8, "burnFuel": 14, "burnRadius": 1, "burnScare": 520,
		"scareRange": 320, "panicTics": 8 * TICRATE, "variants": SHOPPERS, "flat": true, "sway": true,
	}
	var townie: Dictionary = ACTORS["SHOPPER"].duplicate()
	townie.name = "Townsfolk"
	townie.scareRange = 420
	townie.panicTics = 11 * TICRATE
	ACTORS["TOWNIE"] = townie
	ACTORS["SWAT"] = {
		"name": "SWAT", "spawn": "SWAT_STAND", "see": "SWAT_RUN1", "pain": "SWAT_PAIN",
		"missile": "SWAT_ATK1", "death": "SWAT_DIE1", "xdeath": "SWAT_XDIE1",
		"health": 60, "gibHealth": -30, "radius": 20, "height": 56, "mass": 100, "painchance": 50,
		"speed": 9, "reaction": 8, "sightRange": 2400, "missileRange": 1500,
		"monster": true, "team": "law", "fireproof": true,
		"seeSound": "swatsee", "painSound": "swatpain", "deathSound": "swatdie", "attackSound": "shot",
		"freezable": true, "frozen": "SWAT_FROZE", "freezeReturn": "SWAT_RUN1", "bored": "SWAT_BORE", "lit": 1.3,
	}
	ACTORS["ARMY"] = {
		"name": "Soldier", "spawn": "ARMY_STAND", "see": "ARMY_RUN1", "pain": "ARMY_PAIN",
		"missile": "ARMY_ATK1", "death": "ARMY_DIE1", "xdeath": "ARMY_XDIE1",
		"health": 140, "gibHealth": -70, "radius": 22, "height": 58, "mass": 130, "painchance": 32,
		"speed": 10, "reaction": 6, "sightRange": 2800, "missileRange": 1900,
		"monster": true, "team": "law", "fireproof": true,
		"seeSound": "armysee", "painSound": "armypain", "deathSound": "armydie", "attackSound": "rifle",
		"freezable": true, "frozen": "ARMY_FROZE", "freezeReturn": "ARMY_RUN1", "bored": "ARMY_BORE", "lit": 1.1,
	}
	# a street lamp is a post you walk into, and nothing you can see: the
	# geometry and the flare are Lamps' (js/states.js STREETLAMP)
	ACTORS["STREETLAMP"] = {"name": "Street lamp", "radius": 8, "height": 256, "solid": true}
	ACTORS["BLOOD"] = {"name": "Blood", "spawn": "BLUD_REST", "radius": 8, "height": 1}
	# A HEADSTONE: granite, thirty-two tall — it stops you and you can see
	# over it — one of eight photographs by its variant (js/states.js)
	ACTORS["GRAVESTONE"] = {"name": "Headstone", "spawn": "GRAV_STAND", "radius": 10, "height": 32, "solid": true, "variants": 8}
	ACTORS["BLAST"] = {"name": "Blast", "spawn": "BLAST1", "radius": 8, "height": 96, "fullbright": true}
	ACTORS["PUFF"] = {"name": "Puff", "spawn": "PUFF1", "radius": 4, "height": 8}
	# A PARKED VEHICLE's cylinders (added for the vehicles port): no spawn,
	# so no state and no sprite — the vehicle draws itself — and three of
	# these in a row are the part of a van you cannot walk through. Each
	# carries `vehicle`, and its damage and its catching are the van's.
	ACTORS["CARBODY"] = {"name": "Vehicle", "radius": 38, "height": 86, "solid": true,
		"shootable": true, "flammable": true, "health": 100000}

## One troop's whole table, under its own prefix, on its own sprite.
static func _troop(key: String, sprite: String, attack: String) -> void:
	var N := func(n: String) -> String: return key + "_" + n
	_s(N.call("STAND"), sprite, "G", 10, "A_Look", N.call("STAND"))
	var walk := "AABBCCDD"
	for i in 8:
		_s(N.call("RUN%d" % (i + 1)), sprite, walk[i], 3, "A_Chase", N.call("RUN%d" % ((i + 1) % 8 + 1)))
	_s(N.call("ATK1"), sprite, "E", 10, "A_FaceTarget", N.call("ATK2"))
	_s(N.call("ATK2"), sprite, "F", 8, attack, N.call("ATK3"), {"fullbright": true})
	_s(N.call("ATK3"), sprite, "E", 8, "A_FaceTarget", N.call("RUN1"))
	_s(N.call("PAIN"), sprite, "G", 3, null, N.call("PAIN2"))
	_s(N.call("PAIN2"), sprite, "G", 3, "A_Pain", N.call("RUN1"))
	var down := [["H", 5, null], ["I", 5, "A_Scream"], ["J", 5, "A_Fall"], ["K", 6, null], ["L", 6, null], ["M", 6, null]]
	for i in down.size():
		var d: Array = down[i]
		_s(N.call("DIE%d" % (i + 1)), sprite, d[0], d[1], d[2], N.call("DEAD") if i == down.size() - 1 else N.call("DIE%d" % (i + 2)))
	_s(N.call("DEAD"), sprite, "N", -1, null, null)
	var gib := "OPQRSTUVW"
	for i in gib.length():
		var last := i == gib.length() - 1
		var act = "A_XScream" if i == 0 else ("A_Fall" if i == 1 else null)
		_s(N.call("XDIE%d" % (i + 1)), sprite, gib[i], -1 if last else 5, act, null if last else N.call("XDIE%d" % (i + 2)))
	_s(N.call("FROZE"), sprite, "G", -1, null, N.call("FROZE"))
	_s(N.call("BORE"), sprite, "G", -1, null, N.call("BORE"))
