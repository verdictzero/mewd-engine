## MEWD — the texture pack (js/texpack.js, js/texpack-data.js).
##
## Every picture in assets/textures, with the size it covers in the
## world: a pack picture spans its pixel size times its units-per-pixel
## (most are a half — a 256-pixel floor is 128 units). The list is
## godot/data/texpack.json, written from the JS manifest.
class_name TexBank
extends RefCounted

const DIR := "res://assets/textures/"

var info := {}
var _tex := {}
var _mat := {}
var shader: Shader = preload("res://godot/shaders/world.gdshader")

func _init() -> void:
	var f := FileAccess.open("res://godot/data/texpack.json", FileAccess.READ)
	info = JSON.parse_string(f.get_as_text())

## World size of one repeat of `name`, in units.
func size_of(name: String) -> Vector2:
	var e = info.get(name)
	if e == null:
		return Vector2(64, 64)
	return Vector2(e[0] * e[2], e[1] * e[2])

func masked(name: String) -> bool:
	var e = info.get(name)
	return e != null and int(e[3]) != 0

func texture(name: String) -> Texture2D:
	if not _tex.has(name):
		var path := DIR + name + ".png"
		_tex[name] = load(path) if ResourceLoader.exists(path) else load(DIR + "64TEST.png")
	return _tex[name]

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

func all_materials() -> Array:
	return _mat.values()
