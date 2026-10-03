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
## how long a trooper's body lies before it is gone (two seconds)
const CORPSE_TICS := 70

static var STATES := {}
static var ACTORS := {}
static var _built := false

## a person's drawing: 17 in a strip of 40x64 cells
const SHOPPERS := 17
const BLASTS := 26
## the candy girls' flavours, in their strip's order (assets/people/
## candy_girls.png: each one's front, then her back)
const CANDY_FLAVOURS := ["Blueberry", "Cherry Cola", "Grape", "Lemon", "Lime", "Mint", "Strawberry", "Vanilla", "Orange Creamsicle"]

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

	# ---- THE CANDY GIRLS (CANDY LAND, at the user's request): a shopper's
	# table on their own strip, and two more things to do — walk up to you
	# (A_Approach) and stand in front of you saying hello (A_Hello) — until
	# something frightens them; then they run like anybody, for good
	_s("CANDY_STAND", "CANDY", "A", 6, "A_Greet", "CANDY_STAND")
	_s("CANDY_WALK1", "CANDY", "A", 3, "A_Approach", "CANDY_WALK2")
	_s("CANDY_WALK2", "CANDY", "A", 3, "A_Approach", "CANDY_WALK1")
	_s("CANDY_HELLO", "CANDY", "A", 6, "A_Hello", "CANDY_HELLO")
	_s("CANDY_RUN1", "CANDY", "A", 3, "A_Flee", "CANDY_RUN2")
	_s("CANDY_RUN2", "CANDY", "A", 3, "A_Flee", "CANDY_RUN1")
	_s("CANDY_BURN1", "CANDY", "A", 2, "A_Torch", "CANDY_BURN2", {"fullbright": true})
	_s("CANDY_BURN2", "CANDY", "A", 2, "A_Torch", "CANDY_BURN1", {"fullbright": true})
	_s("CANDY_GIB", "CANDY", "A", 1, "A_Gib", null)
	_s("CANDY_FROZE", "CANDY", "A", -1, null, "CANDY_FROZE")
	_s("CANDY_ASH1", "CANDY", "A", 4, "A_BurnAway", "CANDY_ASH2", {"fullbright": true})
	_s("CANDY_ASH2", "CANDY", "A", 4, "A_BurnAway", "CANDY_ASH1", {"fullbright": true})
	_s("CANDY_BORE", "CANDY", "A", -1, null, "CANDY_BORE")
	# THE CANDY UNICORNS (CANDY LAND, at the user's request): grazing and
	# wandering in the meadows by herds, galloping off when frightened
	for k in ["UNI", "FOAL"]:
		_s(k + "_GRAZE", k, "A", 10, "A_Graze", k + "_GRAZE")
		_s(k + "_WALK1", k, "A", 4, "A_Amble", k + "_WALK2")
		_s(k + "_WALK2", k, "A", 4, "A_Amble", k + "_WALK1")
		_s(k + "_RUN1", k, "A", 2, "A_Flee", k + "_RUN2")
		_s(k + "_RUN2", k, "A", 2, "A_Flee", k + "_RUN1")
		_s(k + "_BURN1", k, "A", 2, "A_Torch", k + "_BURN2", {"fullbright": true})
		_s(k + "_BURN2", k, "A", 2, "A_Torch", k + "_BURN1", {"fullbright": true})
		_s(k + "_GIB", k, "A", 1, "A_Gib", null)
		_s(k + "_FROZE", k, "A", -1, null, k + "_FROZE")
		_s(k + "_ASH1", k, "A", 4, "A_BurnAway", k + "_ASH2", {"fullbright": true})
		_s(k + "_ASH2", k, "A", 4, "A_BurnAway", k + "_ASH1", {"fullbright": true})
		_s(k + "_BORE", k, "A", -1, null, k + "_BORE")
	# and the street lamp that lines CANDY LAND's roads
	_s("LAMP_STAND", "LAMP", "A", -1, null, null)

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
		# a round a bite, ten to finish one (Actor.damage `wounds`)
		"wounds": 10,
	}
	var townie: Dictionary = ACTORS["SHOPPER"].duplicate()
	townie.name = "Townsfolk"
	townie.scareRange = 420
	townie.panicTics = 11 * TICRATE
	ACTORS["TOWNIE"] = townie
	# A CANDY GIRL: a townie's body (as easily hurt, as quick to catch,
	# as quick to run) in one of nine flavours, drawn from the front or
	# the back (Standees "CANDY"); `greets` is what sends her to you
	var candy: Dictionary = townie.duplicate()
	candy.merge({"name": "Candy girl", "spawn": "CANDY_STAND", "see": "CANDY_RUN1", "death": "CANDY_GIB",
		"burn": "CANDY_BURN1", "frozen": "CANDY_FROZE", "freezeReturn": "CANDY_RUN1",
		"burnAway": "CANDY_ASH1", "bored": "CANDY_BORE", "variants": CANDY_FLAVOURS.size(),
		"height": 60, "greets": true, "speed": 12}, true)
	ACTORS["CANDYGIRL"] = candy
	# A CANDY UNICORN and her FOAL: drawn from the front, the side or the
	# back by the way they face (Standees "UNI", "FOAL"); they graze about
	# their herd's ground (`herd`, Actor.A_Graze) and gallop when
	# frightened (`runSpeed`); the foal is a little over half her size
	for k in ["UNICORN", "FOAL"]:
		var s: String = "UNI" if k == "UNICORN" else "FOAL"
		var big: bool = k == "UNICORN"
		var u: Dictionary = townie.duplicate()
		u.erase("sway")
		u.merge({"name": "Candy unicorn" if big else "Candy foal", "spawn": s + "_GRAZE", "see": s + "_RUN1",
			"death": s + "_GIB", "burn": s + "_BURN1", "frozen": s + "_FROZE", "freezeReturn": s + "_RUN1",
			"burnAway": s + "_ASH1", "bored": s + "_BORE", "painSound": null,
			"health": 60 if big else 20, "radius": 26 if big else 14, "height": 80 if big else 44,
			"mass": 400 if big else 120, "speed": 3 if big else 2, "runSpeed": 22 if big else 18,
			"scareRange": 520, "panicTics": 7 * TICRATE, "herd": true, "wounds": 14 if big else 8}, true)
		ACTORS[k] = u
	# (sunk 12 units — the clear margin under the post in its picture, and a
	# little for the kerb's slope under its foot — so it always stands IN
	# the ground, at the user's request; Standees reads "sink")
	# A lamp can be shot to pieces (at the user's request: rounds blow holes
	# in every sprite before they destroy it): eight rounds a hole each, the
	# eighth and it goes to pieces of itself (`breaks`, Game.break_apart)
	ACTORS["LAMP"] = {"name": "Street lamp", "spawn": "LAMP_STAND", "radius": 6, "height": 140, "solid": true, "sink": 12.0,
		"shootable": true, "health": 80, "wounds": 8, "breaks": true}
	ACTORS["SWAT"] = {
		"name": "SWAT", "spawn": "SWAT_STAND", "see": "SWAT_RUN1", "pain": "SWAT_PAIN",
		"missile": "SWAT_ATK1", "death": "SWAT_DIE1", "xdeath": "SWAT_XDIE1",
		"health": 60, "gibHealth": -30, "radius": 20, "height": 56, "mass": 100, "painchance": 50,
		"speed": 9, "reaction": 8, "sightRange": 2400, "missileRange": 1500,
		"monster": true, "team": "law", "fireproof": true,
		"seeSound": "swatsee", "painSound": "swatpain", "deathSound": "swatdie", "attackSound": "shot",
		"freezable": true, "frozen": "SWAT_FROZE", "freezeReturn": "SWAT_RUN1", "bored": "SWAT_BORE", "lit": 1.3,
		"wounds": 8,
	}
	ACTORS["ARMY"] = {
		"name": "Soldier", "spawn": "ARMY_STAND", "see": "ARMY_RUN1", "pain": "ARMY_PAIN",
		"missile": "ARMY_ATK1", "death": "ARMY_DIE1", "xdeath": "ARMY_XDIE1",
		"health": 140, "gibHealth": -70, "radius": 22, "height": 58, "mass": 130, "painchance": 32,
		"speed": 10, "reaction": 6, "sightRange": 2800, "missileRange": 1900,
		"monster": true, "team": "law", "fireproof": true,
		"seeSound": "armysee", "painSound": "armypain", "deathSound": "armydie", "attackSound": "rifle",
		"freezable": true, "frozen": "ARMY_FROZE", "freezeReturn": "ARMY_RUN1", "bored": "ARMY_BORE", "lit": 1.1,
		"wounds": 12,
	}
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
	# THE DEAD DO NOT STAY, at the user's request: a body lies CORPSE_TICS
	# and is gone (a null next removes the actor; the pool of blood under
	# it is a decal and stays)
	_s(N.call("DEAD"), sprite, "N", CORPSE_TICS, null, null)
	var gib := "OPQRSTUVW"
	for i in gib.length():
		var last := i == gib.length() - 1
		var act = "A_XScream" if i == 0 else ("A_Fall" if i == 1 else null)
		_s(N.call("XDIE%d" % (i + 1)), sprite, gib[i], CORPSE_TICS if last else 5, act, null if last else N.call("XDIE%d" % (i + 2)))
	_s(N.call("FROZE"), sprite, "G", -1, null, N.call("FROZE"))
	_s(N.call("BORE"), sprite, "G", -1, null, N.call("BORE"))
