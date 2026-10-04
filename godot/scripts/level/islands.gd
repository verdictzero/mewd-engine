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
##            {count, adults: [least, most], foals: [least, most]}
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
	{"key": "island0", "title": "ISLAND 0", "scene": "res://godot/island/scenes/island_0.tscn", "people": 360,
		"blurb": "golf's island, the first one: hills, firs and a cliff all round into the cloud"},
	# ISLAND 0 at half the size and at a quarter (hub_radius 625 and 312.5
	# m against 1250), every other setting the same; the same crowd on less
	# ground, so they are closer together
	{"key": "island-1", "title": "ISLAND -1", "scene": "res://godot/island/scenes/island_-1.tscn", "people": 360,
		"blurb": "ISLAND 0 at half the size"},
	{"key": "island-2", "title": "ISLAND -2", "scene": "res://godot/island/scenes/island_-2.tscn", "people": 360,
		"blurb": "ISLAND 0 at a quarter of the size"},
	# CANDY LAND, at the user's request: ISLAND 0's size and hills, the
	# candy pack's ground and plants, roads between town squares, a blue
	# sky with a candy sun at the top of it, and the candy girls — who come
	# to say hello (Actor.A_Greet) until something frightens them
	{"key": "candyland", "title": "CANDY LAND", "scene": "res://godot/island/scenes/candy_land.tscn", "people": 360,
		"crowd": ["CANDYGIRL"], "air": Color(0.62, 0.8, 1.0), "lamps": 40.0,
		"exposure": 0.8, "knee": 0.65, "road_verge": 3.0, "town_verge": 5.0,
		"herds": {"count": 12, "adults": [3, 6], "foals": [1, 3]},
		# the gingerbread houses round the squares (IslandLevel.place_houses):
		# the model's footprint in metres (half its width, its back and its
		# front from its middle, how high a round has to go to clear it)
		"houses": {"model": "res://godot/island/candy/models/MODEL_candyLandHouse.glb",
			"footprint": {"hw": 3.45, "back": 3.1, "front": 3.7, "top": 5.6},
			"scale": [0.9, 1.15], "inner": 0.85, "outer": 0.65, "gap": 4.0},
		"blurb": "a happy island of candy, roads and sweet girls who want to meet you"},
	# CANDY LAND XS, at the user's request: CANDY LAND at a quarter of the
	# size (hub_radius 312.5 m against 1250, as ISLAND -2 is to ISLAND 0),
	# every other setting the same — so the towns, the herds and the crowd
	# are as many as will fit, on less ground
	{"key": "candyland-xs", "title": "CANDY LAND XS", "scene": "res://godot/island/scenes/candy_land_xs.tscn", "people": 360,
		"crowd": ["CANDYGIRL"], "air": Color(0.62, 0.8, 1.0), "lamps": 40.0,
		"exposure": 0.8, "knee": 0.65, "road_verge": 3.0, "town_verge": 5.0,
		"herds": {"count": 12, "adults": [3, 6], "foals": [1, 3]},
		# the gingerbread houses round the squares (IslandLevel.place_houses):
		# the model's footprint in metres (half its width, its back and its
		# front from its middle, how high a round has to go to clear it)
		"houses": {"model": "res://godot/island/candy/models/MODEL_candyLandHouse.glb",
			"footprint": {"hw": 3.45, "back": 3.1, "front": 3.7, "top": 5.6},
			"scale": [0.9, 1.15], "inner": 0.85, "outer": 0.65, "gap": 4.0},
		"blurb": "CANDY LAND at a quarter of the size"}
]

## The island called `key`, or the first.
static func find(key: String) -> Dictionary:
	for i in LIST:
		if i.key == key:
			return i
	return LIST[0]
