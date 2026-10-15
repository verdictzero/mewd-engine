## THE PLACES the terrain engine draws: real ones made out of open map data
## (tools/earth_fetch.py, EarthField) and golf's procedural island, each a
## scene of the chunked island system (godot/island/). `--map=KEY` picks one;
## the viewer's N key steps through them (godot/scripts/main.gd).
##
##   key      what --map= calls it
##   title    what the viewer says
##   scene    the island's scene: its field, its sky, its plants, its water
##   blurb    a line about it
##   palette  (optional) false: the RETRO picture keeps the island's own
##            colours instead of snapping them to the earth palette
##   exposure (optional) the picture's exposure on this island, 1 as is
##   knee     (optional) where the tonemap's shoulder starts rolling the
##            highlights off instead of clipping them; 0 none (lofi.gdshader)
##   start    (optional) where the camera starts: Vector2(east, south),
##            metres from the island's middle (a real place's middle may be
##            a lake), and "start_face" the point it looks toward
##   sky      (optional, an island with an EnviroSky) {hour, day (of the
##            year), weather (a preset: clear, fair, partly_cloudy, cloudy,
##            overcast, foggy, light_rain, rain, storm, light_snow, snow),
##            day_minutes (real minutes a day; 0 holds the clock)}
##   grade    (optional) the picture's colour grade (Lofi.set_grade)
##   meter    (optional) the picture's meter, the exposure following how
##            bright the picture is as an eye adapts (Lofi.set_meter_spec):
##            {key, strength, least, most}, or {off: true}
class_name Islands
extends RefCounted

const LIST := [
	# OESCHINENSEE: a real place, not a made one — a 3 km square of the
	# Bernese Oberland round the lake under the Bluemlisalp, its ground, its
	# water and its woods out of open map data (tools/earth_fetch.py,
	# EarthField), high-resolution PBR ground and plants rendered from CC0
	# models (tools/earth_pack.py), cut out of the world with a cliff all
	# round into the cloud
	{"key": "earth_oeschinen", "title": "OESCHINENSEE", "scene": "res://godot/island/earth/oeschinen/earth_oeschinen.tscn",
		"blurb": "a real place: 46.4986 N, 7.7270 E, a 3 km square", "palette": false,
		# (on the open pasture by the lake's west shore, where the path up
		# from Kandersteg comes out of the trees, looking up the lake)
		"start": Vector2(-1050, 150), "start_face": Vector2(700, 0),
		# its sky (EnviroSky): a mid-July evening, the sun low in the west
		# over the Kandersteg side and the cliffs at the lake's end in the
		# gold, fair-weather cumulus
		"sky": {"hour": 18.75, "day": 196, "weather": "fair"},
		# (the highlights rolled off from 0.6, for when the meter opens the
		# picture up for a meadow in the shade and the cliffs are in the sun)
		"knee": 0.6,
		# its grade: a film's shoulder, warm, the shadows toward teal and the
		# highlights toward amber, a lens's vignette, grain
		"grade": {"filmic": 1.0, "warmth": 0.2, "contrast": 0.14, "saturation": 1.05,
			"vibrance": 0.2, "split": 0.6, "lift": 0.04, "vignette": 0.32, "grain": 0.035}},
	# NOT PENNSYLVANIA: golf's island, made of noise rather than data — hills,
	# firs and a cliff all round into the cloud
	{"key": "island0", "title": "NOT PENNSYLVANIA", "scene": "res://godot/island/scenes/island_0.tscn",
		"blurb": "golf's procedural island: hills, firs and a cliff all round into the cloud"},
]

## The island called `key`, or the first.
static func find(key: String) -> Dictionary:
	for i in LIST:
		if i.key == key:
			return i
	return LIST[0]
