## MEWD — what the player carries (js/player.js: WEAPONS and the tank
## numbers above it).
##
## Every gun fills itself. There is nothing to pick up: a tank empties
## and fills again, and a tank run DRY latches — the trigger stays dead
## until it is back past a mark (REFIRE_AT and its siblings), so a dry
## weapon is a pause and not a stutter.
class_name Weapons

const TICRATE := 35

const TANK := 420                 # the flamer: twelve seconds of stream
const REGEN_EVERY := 10
const REFIRE_AT := 0.5
const BOTTLE := 260               # the extinguisher's CO2
const CO2_REGEN_EVERY := 6
const CO2_REFIRE_AT := 0.34
const BORES := 5
const BORE_REGEN_EVERY := 12 * TICRATE
const BELT := 3000                # the minigun's belt
const BELT_PER_TIC := 4
const BELT_REGEN_EVERY := 1
const BELT_REFIRE_AT := 0.25
const SPIN_UP := 12
const SPIN_DOWN := 28
const HEAT_UP := 4 * TICRATE
const HEAT_DOWN := 7 * TICRATE
const CHARGE_STAGES := [3, 5, 7]  # the lance: seconds held
const BEAM_SECONDS := [0.6, 0.9, 1.4]
const CELLS := 4
const CELL_REGEN_EVERY := 25 * TICRATE
const CHARGE_WALK := 0.35
const ROCKETS := 4
## the potato cannon's hopper, and a potato back into it every two seconds
const POTATOES := 6
const POTATO_REGEN_EVERY := 2 * TICRATE
const ROCKET_REGEN_EVERY := 2 * TICRATE
const VOLTS := 6
const VOLT_REGEN_EVERY := 3 * TICRATE

const HEALTH := 100
const ARMOUR1 := 5 * HEALTH
const ARMOUR2 := 10 * HEALTH

## the order the slots and the cycle go in
const ORDER := ["FLAMER", "EXTINGUISHER", "BORE", "MINIGUN", "LANCE", "LAUNCHER", "ARC", "POTATO"]

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
}

## the tanks: [cap, refill every n tics, the mark a dry one unlatches at]
const TANKS := {
	"fuel": [TANK, REGEN_EVERY, REFIRE_AT],
	"co2": [BOTTLE, CO2_REGEN_EVERY, CO2_REFIRE_AT],
	"bores": [BORES, BORE_REGEN_EVERY, 0.0],
	"rounds": [BELT, BELT_REGEN_EVERY, BELT_REFIRE_AT],
	"cells": [CELLS, CELL_REGEN_EVERY, 1.0 / CELLS],
	"rockets": [ROCKETS, ROCKET_REGEN_EVERY, 0.0],
	"volts": [VOLTS, VOLT_REGEN_EVERY, 0.0],
	"potatoes": [POTATOES, POTATO_REGEN_EVERY, 0.0],
}

## the minigun's damage: 24 to 48 a round
static func minigun_damage() -> int:
	return 24 + (U.p_random() % 25)

## the flamer's: 8 to 16 a particle
static func flamer_damage() -> int:
	return (U.p_random() % 9) + 8
