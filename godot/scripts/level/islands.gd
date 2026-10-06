## MEWD — THE ISLANDS, at the user's request: every level is an island
## (godot/island/, from golf), pre-built, and this is the list the title's
## level select shows and `--map=` names.
##
##   key      what --map= and a match's map call it
##   title    what the level select says
##   scene    the island's scene: its field, its sky, its plants
##   people   how many townsfolk are dropped on it with you
##   crowd    (optional) who they are, actor types picked from at random;
##            townsfolk and shoppers if not given
##   air      (optional) the colour the air goes far off — the game's own
##            fog on people, marks and effects — matched to the island's sky
##   palette  (optional) false: the picture keeps the island's own colours
##            instead of being snapped to the earth palette (the dither stays)
##   exposure (optional) the picture's exposure on this island, 1 as is
##   knee     (optional) where the tonemap's shoulder starts rolling the
##            highlights off instead of clipping them; 0 none (lofi.gdshader)
##   herds    (optional) herds of candy unicorns in the meadows:
##            {count, adults: [least, most], foals: [least, most],
##            near: how many of them graze in sight of your start, by_towns:
##            one more in sight of every town} — the crowd is not drawn past
##            200 m (Standees.CULL_FAR), and herds anywhere on the island
##            were herds nobody saw (at the user's request: "haven't seen
##            any unicorns yet")
##   lamps    (optional) street lamps along the island's roads, this far
##            apart in metres
##   road_verge (optional) the roads and towns drawn off their own lines
##            (Game._road_uniforms): a strip of grass this many metres wide
##            either side of every road, the road's texture along it
##   town_verge (optional, with road_verge) a square town paved to this
##            many metres inside its edge, grass from there to the bank
class_name Islands
extends RefCounted

const LIST := [
	# (ISLAND 0 renamed NOT PENNSYLVANIA at the user's request; its key is
	# still island0. Its half- and quarter-size copies, ISLAND -1 and -2,
	# are gone, as is CANDY LAND XS, at the user's request)
	{"key": "island0", "title": "NOT PENNSYLVANIA", "scene": "res://godot/island/scenes/island_0.tscn", "people": 360,
		"blurb": "golf's island, the first one: hills, firs and a cliff all round into the cloud",
		# its own music, at the user's request: "Waiting for Something" (the
		# title's until Ocelot took over), crossfading into itself
		"music": ["res://assets/music/waiting_for_something.mp3"],
		# THE PICKUPS (game/pickups.gd): ten round each of the crowd's
		# gathering places — the island has no roads and no towns
		"pickups": {"country": 10}},
	# CANDY LAND, at the user's request: ISLAND 0's size and hills, the
	# candy pack's ground and plants, roads between town squares, a blue
	# sky with a candy sun at the top of it, and the candy girls — who come
	# to say hello (Actor.A_Greet) until something frightens them
	{"key": "candyland", "title": "CANDY LAND", "scene": "res://godot/island/scenes/candy_land.tscn", "people": 600,
		"crowd": ["CANDYGIRL"], "air": Color(0.62, 0.8, 1.0), "lamps": 40.0,
		"exposure": 0.8, "knee": 0.65, "road_verge": 3.0, "town_verge": 5.0,
		"herds": {"count": 36, "adults": [4, 8], "foals": [1, 3], "near": 3, "by_towns": true},
		# the gingerbread houses round the squares (IslandLevel.place_houses):
		# the model's footprint in metres (half its width, its back and its
		# front from its middle, how high a round has to go to clear it)
		"houses": {"model": "res://godot/island/candy/models/MODEL_candyLandHouse.glb",
			"footprint": {"hw": 3.45, "back": 3.1, "front": 3.7, "top": 5.6},
			"scale": [0.9, 1.15], "inner": 0.85, "outer": 0.65, "gap": 4.0},
		# its own music, crossfading one into the other round and round
		# (Music.start_list, at the user's request)
		"music": ["res://assets/music/golf_course_muzak.mp3", "res://assets/music/sunny_resort_groove.mp3",
			"res://assets/music/sunny_fairway.mp3"],
		"pickups": {"country": 6},
		"blurb": "a happy island of candy, roads and sweet girls who want to meet you"},
	# DEBUG LAND, at the user's request: "a 512 x 512 flat square, in the
	# biome and rendering style of Not Pennsylvania" — NOT PENNSYLVANIA's
	# scene and ground, squared and flattened (ISLANDFIELD_debugland.tres)
	{"key": "debugland", "title": "DEBUG LAND", "scene": "res://godot/island/scenes/debug_land.tscn", "people": 60,
		"music": ["res://assets/music/waiting_for_something.mp3"],
		# a SHOWROOM of the twelve pickups ahead of where you land, and
		# everything back half a minute after it is taken
		"pickups": {"country": 4, "respawn": 1050, "showroom": true},
		"blurb": "a flat square of NOT PENNSYLVANIA, 512 metres a side, for trying things out"}
]

## The island called `key`, or the first.
static func find(key: String) -> Dictionary:
	for i in LIST:
		if i.key == key:
			return i
	return LIST[0]
