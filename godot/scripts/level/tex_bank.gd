## MEWD — the texture pack (js/texpack.js, js/texpack-data.js).
##
## Every picture in assets/textures, with the size it covers in the
## world: a pack picture spans its pixel size times its units-per-pixel
## (most are a half — a 256-pixel floor is 128 units). The list is
## godot/data/texpack.json, written from the JS manifest.
class_name TexBank
extends RefCounted

const DIR := "res://assets/textures/"

## THE GAME'S OWN PICTURES, which are not the pack's: the cemetery iron
## (a photograph, js/textures.js RAILING) and the grid's floor and wall
## (gridPix there), written by tools/godot-data.mjs — [path, world w,
## world h, masked, smooth]
const OWN := {
	"RAILING": ["res://godot/data/cemfence.png", 64, 96, true, false],
	"GRID": ["res://godot/data/grid.png", 64, 64, false, true],
	"GRIDWALL": ["res://godot/data/gridwall.png", 64, 64, false, true],
}

## THE MAP'S OWN TEXTURES, made in the editor's texture editor
## (js/editor/texcompose.js, godot/scripts/editor/ed_texcompose.gd) and
## registered here by name while that map is open or being played:
## name -> [Texture2D, world w, world h, masked]
static var map_own := {}

static func register_map_texture(name: String, tex: Texture2D, world_w: float, world_h: float, masked: bool) -> void:
	map_own[name] = [tex, world_w, world_h, masked]

var info := {}
var _tex := {}
var _mat := {}
var _tmat := {}
var shader: Shader = preload("res://godot/shaders/world.gdshader")
var tint_shader: Shader = preload("res://godot/shaders/world_tint.gdshader")

func _init() -> void:
	var f := FileAccess.open("res://godot/data/texpack.json", FileAccess.READ)
	info = JSON.parse_string(f.get_as_text())

## World size of one repeat of `name`, in units.
func size_of(name: String) -> Vector2:
	if map_own.has(name):
		return Vector2(map_own[name][1], map_own[name][2])
	if OWN.has(name):
		return Vector2(OWN[name][1], OWN[name][2])
	var e = info.get(name)
	if e == null:
		return Vector2(64, 64)
	return Vector2(e[0] * e[2], e[1] * e[2])

func masked(name: String) -> bool:
	if map_own.has(name):
		return map_own[name][3]
	if OWN.has(name):
		return OWN[name][3]
	var e = info.get(name)
	return e != null and int(e[3]) != 0

func texture(name: String) -> Texture2D:
	if not _tex.has(name) and map_own.has(name):
		_tex[name] = TexBank.decoded(map_own[name][0])
	if not _tex.has(name):
		var path: String = OWN[name][0] if OWN.has(name) else DIR + name + ".png"
		var t: Texture2D = load(path) if ResourceLoader.exists(path) else load(DIR + "64TEST.png")
		_tex[name] = TexBank.decoded(t)
	return _tex[name]

## THE PICTURE AS THE WEB BUILD SAMPLES IT. Every picture there is an
## SRGBColorSpace texture, which WebGL decodes to linear on the fetch, and
## the frame is written out without being encoded again (the lo-fi
## buffer is a plain byte target, and nothing calls linearToOutputTexel):
## so a surface is drawn at its picture's LINEAR value times its light —
## darker in the middle tones than the picture itself. Godot's
## Compatibility renderer does neither (a source_color fetch comes back
## as the bytes, and ALBEDO goes out as it is), so the same darkening is
## done here, once, to the picture.
static func decoded(t: Texture2D, mips := true) -> Texture2D:
	var img := t.get_image()
	if img == null:
		return t
	img = img.duplicate()
	if img.is_compressed():
		img.decompress()
	img.clear_mipmaps()
	img.convert(Image.FORMAT_RGBA8)
	img.srgb_to_linear()
	if mips:
		img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

## The world material wearing `name` — one per texture, shared, so the
## whole level changes with one uniform.
func material(name: String) -> ShaderMaterial:
	if not _mat.has(name):
		var m := ShaderMaterial.new()
		m.shader = shader
		m.set_shader_parameter("tex", texture(name))
		m.set_shader_parameter("masked", masked(name))
		_mat[name] = m
	return _mat[name]


## The same, under the TINTED world shader (godot/shaders/world_tint.
## gdshader): a sector's Doom 64 colours and its fog, per vertex, the
## map's ambient light and default fog, faces culled — what an edited
## map's surfaces wear (MapGeo, when the level asks). The smooth pictures
## (the grid) are filtered, as the web build filters them.
func material_tinted(name: String) -> ShaderMaterial:
	if not _tmat.has(name):
		var m := ShaderMaterial.new()
		m.shader = tint_shader
		m.set_shader_parameter("tex", texture(name))
		m.set_shader_parameter("masked", masked(name))
		var smooth: bool = OWN.has(name) and OWN[name][4]
		m.set_shader_parameter("use_smooth", smooth)
		if smooth:
			m.set_shader_parameter("tex_smooth", texture(name))
		_tmat[name] = m
	return _tmat[name]

## The map's own light on every tinted material (applyMapLight in
## js/material.js): its ambient light, its default fog and how much of
## the ambient is in the fog.
func set_map_light(ml: Dictionary) -> void:
	for m in _tmat.values():
		var a: Color = ml.get("ambient", Color.BLACK)
		var f: Color = ml.get("fog", Color(0, 0, 0, 0))
		m.set_shader_parameter("ambient", Vector3(a.r, a.g, a.b))
		m.set_shader_parameter("fog_default", Vector4(f.r, f.g, f.b, f.a))
		m.set_shader_parameter("fog_ambient", float(ml.get("fogAmbient", 1.0)))

func all_materials() -> Array:
	return _mat.values() + _tmat.values()
