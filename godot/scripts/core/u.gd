## THE NUMBERS AND HELPERS everything shares.
class_name U

## THE BUILD'S NUMBER (seven places, leading zeroes, one string; one more on
## every change that ships). The builds' own (project.godot,
## export_presets.cfg) are kept the same.
const VERSION := "0000040"

## THE GLOBAL SHADER UNIFORMS, as last set: every one is set through gset,
## which keeps a copy here, because the Mobile renderer will not read one
## back outside the editor.
static var G := {}

static func gset(name: String, value) -> void:
	G[name] = value
	RenderingServer.global_shader_parameter_set(name, value)

## A COLOUR FOR A MATERIAL'S UNIFORM, the same under both renderers. Mobile
## takes a Color handed to a material as sRGB and decodes it to linear, hint
## or no hint; Compatibility hands it over as it is. So under Mobile it is
## encoded first, and the decode lands on the value meant. Anything that is
## not a Color passes. (The global uniforms are not touched by either.)
static var _rd := -1
static func col(v):
	if not (v is Color):
		return v
	if _rd < 0:
		_rd = 1 if RenderingServer.get_rendering_device() != null else 0
	return (v as Color).linear_to_srgb() if _rd == 1 else v

## A 3D VIEWPORT WHOSE PICTURE IS READ AS NUMBERS, the same under both
## renderers. Compatibility writes a fragment's colour out as it is; Mobile
## encodes it to sRGB on the way out unless the viewport is HDR, so under
## Mobile it is made HDR and its picture is the raw colour, as it was. (And
## the engine's shaders mark no texture or colour source_color where the
## picture is read as numbers: Compatibility ignores the hint, and Mobile
## would decode what it marks.)
static func raw_out(v: SubViewport) -> void:
	if RenderingServer.get_rendering_device() != null:
		v.use_hdr_2d = true

## The interface's face: DejaVu (shipped), at a weight.
static func ui_font(mono := false, weight := 400) -> Font:
	var bold := weight >= 600
	return load("res://assets/fonts/dejavu/DejaVuSans%s%s.ttf" % ["Mono" if mono else "", "-Bold" if bold else ""])
