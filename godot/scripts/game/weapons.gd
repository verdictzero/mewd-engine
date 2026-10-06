## MEWD — what the player carries (js/player.js: WEAPONS and the tank
## numbers above it).
##
## THE TANKS ARE WHAT YOU CARRY, at the user's request ("make finite ammo
## and health a thing"): a gun spends its tank and nothing fills it but
## what you walk over (game/pickups.gd) — save the two with nothing to
## pick up for them, the flamer's fuel (the gun you always have: it
## trickles back to a pilot's worth, FUEL_FLOOR) and the extinguisher's
## CO2. A tank run DRY still latches — the trigger stays dead until it
## is back past a mark, or until a pickup puts something in it.
class_name Weapons

const TICRATE := 35

const TANK := 420                 # the flamer: twelve seconds of stream
## (a PILOT LIGHT: it trickles back, a unit every REGEN_EVERY tics, as
## far as FUEL_FLOOR, four seconds of stream; and a dry one is going again
## at a twelfth, a second of it, seven seconds after it ran out — never a
## lock-out)
const REGEN_EVERY := 7
const FUEL_FLOOR := 140
const REFIRE_AT := 1.0 / 12.0
const BOTTLE := 260               # the extinguisher's CO2: it fills itself
const CO2_REGEN_EVERY := 6
const CO2_REFIRE_AT := 0.34
const BORES := 8
const BELT := 2000                # the minigun's belt: the most you can carry, 14 s of trigger
const BELT_PER_TIC := 4
const BELT_REFIRE_AT := 0.25
const SPIN_UP := 12
const SPIN_DOWN := 28
const HEAT_UP := 4 * TICRATE
const HEAT_DOWN := 7 * TICRATE
const CHARGE_STAGES := [3, 5, 7]  # the lance: seconds held
const BEAM_SECONDS := [0.6, 0.9, 1.4]
const CELLS := 6
const CHARGE_WALK := 0.35
const ROCKETS := 16
## the potato cannon's hopper
const POTATOES := 6
const VOLTS := 12
## THE PLASMA RIFLE (the Sarakawa Mk II, game/plasma.gd): forty cells
## carried; its screen shows the next ten (PLASMA_CLIP)
const PLASMA_CELLS := 40
const PLASMA_CLIP := 10

## HEALTH AND ARMOUR, at the user's request ("make finite ... health a
## thing, as well as armor on top of health"). Health heals to HEALTH;
## only the big medkit takes it past, to HEALTH_TOP, and over HEALTH it
## bleeds back a point every OVERHEAL_EVERY tics. ARMOUR is one pool on
## top of it with a CLASS (Doom's green and blue): each blow, the class's
## share of it (ARMOUR_SOAK) is taken by the armour while there is
## armour left, and the rest by you.
const HEALTH := 100
const HEALTH_TOP := 150
const OVERHEAL_EVERY := TICRATE
const ARMOUR_MAX := 200
## none, light (the small armour), heavy (the big)
const ARMOUR_SOAK := [0.0, 1.0 / 3.0, 0.5]
## what a life in single player starts with
const START_HEALTH := 100
const START_ARMOUR := 50
const START_ARMOUR_CLASS := 1

## the order the slots and the cycle go in
const ORDER := ["FLAMER", "EXTINGUISHER", "BORE", "MINIGUN", "LANCE", "LAUNCHER", "ARC", "POTATO", "PLASMA"]

const WEAPONS := {
	"FLAMER": {"slot": 1, "name": "FLAMER", "fireTics": [2, 2], "ammo": "fuel", "ammoPerShot": 0,
		"autofire": true, "refire": REFIRE_AT, "stream": "fire", "sound": "flame"},
	"EXTINGUISHER": {"slot": 2, "name": "EXTINGUISHER", "fireTics": [2, 2], "ammo": "co2", "ammoPerShot": 0,
		"autofire": true, "refire": CO2_REFIRE_AT, "stream": "frost", "sound": "flame"},
	"BORE": {"slot": 3, "name": "CEREBRAL BORE", "fireTics": [5, 14], "ammo": "bores", "ammoPerShot": 1,
		"lock": true, "sound": "borefire"},
	"MINIGUN": {"slot": 4, "name": "MINIGUN", "fireTics": [1, 1], "ammo": "rounds", "ammoPerShot": 0,
		"autofire": true, "refire": BELT_REFIRE_AT, "volley": true, "rounds": BELT_PER_TIC, "spread": 0.055},
	"LANCE": {"slot": 5, "name": "POSITRON LANCE", "fireTics": [4, 4], "ammo": "cells", "ammoPerShot": 1, "charge": true},
	"LAUNCHER": {"slot": 6, "name": "QUAD LAUNCHER", "fireTics": [3, 3], "ammo": "rockets", "ammoPerShot": 1, "seeker": true},
	"ARC": {"slot": 7, "name": "ARC MAW", "fireTics": [3, 5], "ammo": "volts", "ammoPerShot": 1, "arc": true},
	# (game/potatoes.gd)
	"POTATO": {"slot": 8, "name": "IRISH POTATO CANNON", "fireTics": [20], "ammo": "potatoes", "ammoPerShot": 1, "potato": true},
	# THE SARAKAWA MK II, at the user's request ("single shot plasma rifle,
	# semi-auto fire rate, precise, thick long pellet beam"): one bolt a
	# pull of the trigger (`semi`: let go to fire again), no spread, at
	# most about three a second (game/plasma.gd)
	"PLASMA": {"slot": 9, "name": "SARAKAWA MK II", "fireTics": [6, 6], "ammo": "plasma", "ammoPerShot": 1, "semi": true, "plasma": true},
}

## the tanks: [the most you carry, refill one every n tics (0: never —
## there are pickups for it), the mark a dry one unlatches at, and the
## most it refills itself to]
const TANKS := {
	"fuel": [TANK, REGEN_EVERY, REFIRE_AT, FUEL_FLOOR],
	"co2": [BOTTLE, CO2_REGEN_EVERY, CO2_REFIRE_AT, BOTTLE],
	"bores": [BORES, 0, 0.0, 0],
	"rounds": [BELT, 0, BELT_REFIRE_AT, 0],
	"cells": [CELLS, 0, 0.0, 0],
	"rockets": [ROCKETS, 0, 0.0, 0],
	"volts": [VOLTS, 0, 0.0, 0],
	"potatoes": [POTATOES, 0, 0.0, 0],
	"plasma": [PLASMA_CELLS, 0, 0.0, 0],
}

## what a life in single player starts with in each (a match has its
## own: NetMatch.RULES spawnAmmo)
const START := {
	"fuel": TANK, "co2": BOTTLE, "bores": 3, "rounds": 600, "cells": 2,
	"rockets": 4, "volts": 3, "potatoes": 0, "plasma": 10,
}

## where the readout's count of a tank turns amber (Hud): what a fight
## or two of it is, not a fraction of what it holds
const LOW := {
	"rounds": 300, "plasma": 5, "cells": 1, "rockets": 4, "volts": 1, "bores": 1,
	"potatoes": 1, "fuel": 140, "co2": 88,
}

## what one shot of a gun needs in the tank (a volley takes its rounds
## all at once)
static func need(w: String) -> int:
	var d: Dictionary = WEAPONS[w]
	return maxi(1, int(d.get("rounds", d.get("ammoPerShot", 1))))

## the minigun's damage: 24 to 48 a round
static func minigun_damage() -> int:
	return 24 + (U.p_random() % 25)

## the plasma rifle's: 110 to 150 a bolt
static func plasma_damage() -> int:
	return 110 + (U.p_random() % 41)

## the flamer's: 8 to 16 a particle
static func flamer_damage() -> int:
	return (U.p_random() % 9) + 8
