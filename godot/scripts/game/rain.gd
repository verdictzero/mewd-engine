## MEWD — rain (js/rain.js).
##
## Streaks in a box round the eye, falling fast and leaning with the
## wind, spawned only over ground with sky above it (outdoors, the wood,
## the road, a gutted roof) and gone where they meet the floor. How much
## of it is the weather's `rain`; nothing in a clear night.
class_name Rain
extends RefCounted

const FALL := 8.0
const LIFE := 44
const POOL := 2048
const BOX := 520.0
const ABOVE := 80.0
const TOP := 300.0

var game
var pool: Particles

func _init(g) -> void:
	game = g
	# a streak: two columns of pale blue, softer at the ends
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	for y in 8:
		var a := 90 if (y < 1 or y > 6) else 190
		img.set_pixel(3, y, Color8(200, 214, 236, a))
		img.set_pixel(4, y, Color8(168, 184, 212, roundi(a * 0.55)))
	pool = Particles.new({"max": POOL, "map": ImageTexture.create_from_image(img), "frames": 1,
		"blend": "mix", "fullbright": false, "near_shrink": 24.0})
	pool.mat.set_shader_parameter("light", 0.5)

func tic() -> void:
	var rain: float = game.weather.frame.get("rain", 0.0)
	var p = game.player
	var lv: Level = game.level
	if rain > 0.0 and p != null:
		var w: Vector2 = game.weather.wind()
		var lean := LIFE * 0.5
		for i in roundi(60.0 * rain):
			var x: float = p.x + (U.p_random() / 255.0 - 0.5) * 2.0 * BOX - w.x * lean
			var y: float = p.y + (U.p_random() / 255.0 - 0.5) * 2.0 * BOX - w.y * lean
			var s := lv.sector_at(x, y)
			# rain falls from the sky onto the top of a column
			if s != null and s.above != -1:
				s = lv.top_of(s)
			if s == null or not (s.outdoor or s.props.get("forest", false) or s.props.get("outside", false)):
				continue
			var a := 0.55 + rain * 0.25
			pool.spawn({"x": x, "y": y, "z": p.view_z + ABOVE + (U.p_random() / 255.0) * (TOP - ABOVE),
				"vx": w.x * 2.2 + (U.p_random() / 255.0 - 0.5) * 0.3, "vy": w.y * 2.2 + (U.p_random() / 255.0 - 0.5) * 0.3,
				"vz": -FALL - (U.p_random() / 255.0) * 2.0, "life": LIFE, "size0": 18.0, "size1": 18.0,
				"c0": Color(1, 1, 1, a), "c1": Color(1, 1, 1, a)})
	pool.tic(func(_i, nx, ny, nz):
		var s := lv.span_at(nx, ny, nz)
		return s == null or nz <= s.floor + 2.0)
