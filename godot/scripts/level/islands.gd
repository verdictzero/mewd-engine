## MEWD — THE ISLANDS, at the user's request: every level is an island
## (godot/island/, from golf), pre-built, and this is the list the title's
## level select shows and `--map=` names.
##
##   key      what --map= and a match's map call it
##   title    what the level select says
##   scene    the island's scene: its field, its sky, its plants
##   people   how many townsfolk are dropped on it with you
class_name Islands
extends RefCounted

const LIST := [
	{"key": "island0", "title": "ISLAND 0", "scene": "res://godot/island/scenes/island_0.tscn", "people": 360,
		"blurb": "golf's island, the first one: hills, firs and a cliff all round into the cloud"},
	# ISLAND 0 at half the size and at a quarter (hub_radius 625 and 312.5
	# m against 1250), every other setting the same; the same crowd on less
	# ground, so they are closer together
	{"key": "island-1", "title": "ISLAND -1", "scene": "res://godot/island/scenes/island_-1.tscn", "people": 360,
		"blurb": "ISLAND 0 at half the size"},
	{"key": "island-2", "title": "ISLAND -2", "scene": "res://godot/island/scenes/island_-2.tscn", "people": 360,
		"blurb": "ISLAND 0 at a quarter of the size"},
]

## The island called `key`, or the first.
static func find(key: String) -> Dictionary:
	for i in LIST:
		if i.key == key:
			return i
	return LIST[0]
