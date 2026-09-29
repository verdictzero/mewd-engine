## MEWD Editor — the map's own textures (js/editor/texcompose.js).
##
## A texture made in the texture editor is a stack of LAYERS drawn onto a
## picture of its own size, SLADE's way (and Doom's, out of patches):
## each layer is one of the game's textures or an imported image, placed
## at an offset, scaled, turned by quarter turns, flipped, tiled or drawn
## once, tinted, blended (normal, multiply, screen, add, overlay) and
## faded. It lives IN THE MAP (doc.textures) as the web build keeps it —
## an imported picture as a PNG data URL — and is drawn again whenever
## the map is opened or played, and handed to TexBank under its name.
class_name EdTex

const TEX_MAX := 512
const BLENDS := ["normal", "multiply", "screen", "add", "overlay"]

## A texture's name, as the bank keys it: capitals, digits, _ and -.
static func clean_name(n) -> String:
	var s := str(n if n != null else "").to_upper()
	var out := ""
	for c in s:
		if (c >= "A" and c <= "Z") or (c >= "0" and c <= "9") or c == "_" or c == "-":
			out += c
	return out.substr(0, 16)

static func new_layer(tex = "GRIDWALL") -> Dictionary:
	return {"tex": tex, "image": null, "x": 0, "y": 0, "sx": 1, "sy": 1, "rot": 0, "flipX": false, "flipY": false,
		"tile": true, "tint": "#ffffff", "blend": "normal", "alpha": 1, "hidden": false}

static func new_texture(name: String, from := "GRIDWALL", size := Vector2i(128, 128)) -> Dictionary:
	return {"name": clean_name(name), "w": size.x, "h": size.y, "worldW": size.x, "worldH": size.y, "layers": [new_layer(from)]}

## What is wrong with a definition, or "".
static func check(def, built_in: Dictionary) -> String:
	if not def is Dictionary or clean_name(def.get("name", "")) == "":
		return "it has no name"
	if built_in.has(def.name):
		return "%s is one of the game's own textures" % def.name
	var w := EdDoc.num(def.get("w"), 0)
	var h := EdDoc.num(def.get("h"), 0)
	if not (w >= 1 and w <= TEX_MAX and h >= 1 and h <= TEX_MAX):
		return "it must be 1 to %d pixels each way" % TEX_MAX
	if not def.get("layers") is Array:
		return "it has no layers"
	return ""

static var _images := {}

## An imported picture (a data URL), decoded once.
static func image_from_url(src: String) -> Image:
	if _images.has(src):
		return _images[src]
	var img: Image = null
	var comma := src.find(",")
	if src.begins_with("data:") and comma > 0:
		var head := src.substr(0, comma)
		var raw := Marshalls.base64_to_raw(src.substr(comma + 1))
		img = Image.new()
		var err := ERR_FILE_UNRECOGNIZED
		if head.contains("png"):
			err = img.load_png_from_buffer(raw)
		elif head.contains("jpeg") or head.contains("jpg"):
			err = img.load_jpg_from_buffer(raw)
		elif head.contains("webp"):
			err = img.load_webp_from_buffer(raw)
		if err != OK:
			for f in ["load_png_from_buffer", "load_jpg_from_buffer", "load_webp_from_buffer"]:
				if img.call(f, raw) == OK:
					err = OK
					break
		if err != OK:
			img = null
		else:
			img.convert(Image.FORMAT_RGBA8)
	_images[src] = img
	return img

## A picture as a PNG data URL, as the web build stores an import.
static func image_to_url(img: Image) -> String:
	return "data:image/png;base64," + Marshalls.raw_to_base64(img.save_png_to_buffer())

## The picture of one of the game's textures (or an earlier map
## texture), as the file has it.
static func source_image(name: String, drawn: Dictionary) -> Image:
	if drawn.has(name):
		return drawn[name]
	var path := ""
	if TexBank.OWN.has(name):
		path = TexBank.OWN[name][0]
	else:
		path = TexBank.DIR + name + ".png"
	if not ResourceLoader.exists(path):
		return null
	var t: Texture2D = load(path)
	var img := t.get_image()
	if img == null:
		return null
	img = img.duplicate()
	if img.is_compressed():
		img.decompress()
	img.clear_mipmaps()
	img.convert(Image.FORMAT_RGBA8)
	return img

## Draw a texture: an Image def.w by def.h (composeTexture).
static func compose(def: Dictionary, drawn := {}) -> Image:
	var W := clampi(int(EdDoc.num(def.get("w"), 64)), 1, TEX_MAX)
	var H := clampi(int(EdDoc.num(def.get("h"), 64)), 1, TEX_MAX)
	var out := Image.create(W, H, false, Image.FORMAT_RGBA8)
	out.fill(Color(0, 0, 0, 0))
	for L in def.get("layers", []):
		if L.get("hidden", false):
			continue
		var src: Image = null
		if L.get("image") != null and str(L.image) != "":
			src = image_from_url(str(L.image))
		elif L.get("tex") != null:
			src = source_image(str(L.tex), drawn)
		if src == null:
			continue
		var sheet := _sheet(src, L, W, H)
		var tint := EdDoc.col(L.get("tint", "#ffffff"), Color.WHITE)
		_blend(out, sheet, str(L.get("blend", "normal")), clampf(EdDoc.num(L.get("alpha"), 1.0), 0.0, 1.0), tint)
	return out

## One layer on a sheet of its own the size of the texture.
static func _sheet(src: Image, L: Dictionary, W: int, H: int) -> Image:
	var sheet := Image.create(W, H, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0, 0, 0, 0))
	var sx := EdDoc.num(L.get("sx"), 1.0)
	var sy := EdDoc.num(L.get("sy"), 1.0)
	if sx == 0:
		sx = 1
	if sy == 0:
		sy = 1
	var sw := src.get_width() * sx
	var sh := src.get_height() * sy
	var iw := maxi(1, roundi(absf(sw)))
	var ih := maxi(1, roundi(absf(sh)))
	var pic: Image = src.duplicate()
	if iw != pic.get_width() or ih != pic.get_height():
		pic.resize(iw, ih, Image.INTERPOLATE_NEAREST)
	if L.get("flipX", false):
		pic.flip_x()
	if L.get("flipY", false):
		pic.flip_y()
	var rot := posmod(int(EdDoc.num(L.get("rot"), 0)), 4)
	for i in rot:
		pic.rotate_90(CLOCKWISE)
	var rw := pic.get_width()
	var rh := pic.get_height()
	var place := func(x: float, y: float) -> void:
		var px := roundi(x + sw / 2.0 - rw / 2.0)
		var py := roundi(y + sh / 2.0 - rh / 2.0)
		sheet.blend_rect(pic, Rect2i(0, 0, rw, rh), Vector2i(px, py))
	var lx := EdDoc.num(L.get("x"), 0)
	var ly := EdDoc.num(L.get("y"), 0)
	if L.get("tile", true) and sw >= 1 and sh >= 1:
		var ox := fposmod(lx, sw) - sw
		var oy := fposmod(ly, sh) - sh
		var y := oy
		while y < H:
			var x := ox
			while x < W:
				place.call(x, y)
				x += sw
			y += sh
	else:
		place.call(lx, ly)
	return sheet

## The sheet onto the texture: tinted, faded and blended.
static func _blend(dst: Image, src: Image, mode: String, alpha: float, tint: Color) -> void:
	var d := dst.get_data()
	var s := src.get_data()
	var n := d.size()
	var tr := tint.r
	var tg := tint.g
	var tb := tint.b
	var i := 0
	while i < n:
		var sa := s[i + 3] / 255.0 * alpha
		if sa <= 0.0:
			i += 4
			continue
		var cs := [s[i] / 255.0 * tr, s[i + 1] / 255.0 * tg, s[i + 2] / 255.0 * tb]
		var da := d[i + 3] / 255.0
		var cb := [d[i] / 255.0, d[i + 1] / 255.0, d[i + 2] / 255.0]
		var ra := 0.0
		var rc := [0.0, 0.0, 0.0]
		if mode == "add":
			ra = minf(1.0, sa + da)
			for c in 3:
				rc[c] = minf(1.0, (cs[c] * sa + cb[c] * da) / maxf(ra, 1e-6))
		else:
			ra = sa + da * (1.0 - sa)
			for c in 3:
				var mixd: float = cs[c]
				if mode == "multiply":
					mixd = cs[c] * cb[c]
				elif mode == "screen":
					mixd = cs[c] + cb[c] - cs[c] * cb[c]
				elif mode == "overlay":
					mixd = 2.0 * cs[c] * cb[c] if cb[c] <= 0.5 else 1.0 - 2.0 * (1.0 - cs[c]) * (1.0 - cb[c])
				var src_c: float = (1.0 - da) * cs[c] + da * mixd
				rc[c] = (src_c * sa + cb[c] * da * (1.0 - sa)) / maxf(ra, 1e-6)
		d[i] = clampi(roundi(rc[0] * 255.0), 0, 255)
		d[i + 1] = clampi(roundi(rc[1] * 255.0), 0, 255)
		d[i + 2] = clampi(roundi(rc[2] * 255.0), 0, 255)
		d[i + 3] = clampi(roundi(ra * 255.0), 0, 255)
		i += 4
	dst.set_data(dst.get_width(), dst.get_height(), false, Image.FORMAT_RGBA8, d)

static func has_holes(img: Image) -> bool:
	var d := img.get_data()
	var i := 3
	while i < d.size():
		if d[i] < 128:
			return true
		i += 4
	return false

## The names every game texture goes by (a map texture may not take one).
static func built_in() -> Dictionary:
	var out := {}
	var f := FileAccess.open("res://godot/data/texpack.json", FileAccess.READ)
	if f != null:
		var info = JSON.parse_string(f.get_as_text())
		if info is Dictionary:
			for k in info:
				out[k] = true
	for k in TexBank.OWN:
		out[k] = true
	return out

## Draw every texture a map has and hand them to TexBank under their own
## names — one made of another drawn after it. Returns {name: Image}.
static func register_all(doc: Dictionary) -> Dictionary:
	var defs: Array = doc.get("textures", [])
	TexBank.map_own.clear()
	var by := {}
	for d in defs:
		if d is Dictionary:
			by[str(d.get("name", ""))] = d
	var order := []
	var state := {}
	var visit := func(d: Dictionary, f: Callable) -> void:
		var nm := str(d.get("name", ""))
		if state.has(nm):
			return
		state[nm] = 1
		for L in d.get("layers", []):
			var t = L.get("tex")
			if t != null and by.has(str(t)) and str(t) != nm:
				f.call(by[str(t)], f)
		state[nm] = 2
		order.append(d)
	for d in by.values():
		visit.call(d, visit)
	var BI := built_in()
	var drawn := {}
	for def in order:
		if check(def, BI) != "":
			continue
		var img := compose(def, drawn)
		drawn[def.name] = img
		TexBank.register_map_texture(def.name, ImageTexture.create_from_image(img),
			EdDoc.num(def.get("worldW"), img.get_width()), EdDoc.num(def.get("worldH"), img.get_height()), has_holes(img))
	return drawn
