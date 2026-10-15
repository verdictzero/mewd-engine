class_name EnviroWeather
extends Resource

## ONE WEATHER for EnviroSky (SCRIPT_enviro_sky.gd), as Enviro keeps its
## weather types: a named set of numbers the sky blends to over its transition
## time. The presets are godot/island/sky/enviro/weather/*.tres; a new one is a
## copy of one of those with its numbers moved.

## What the sky and the menus call it.
@export var id := "fair"

@export_group("Clouds")
## How much of the sky can hold cloud, 0 none to 1 every bit.
@export_range(0.0, 1.0) var coverage := 0.35
## How thick they are: their extinction per metre.
@export_range(0.0, 0.2) var density := 0.035
## Their shape, 0 a flat stratus sheet to 1 towering cumulus.
@export_range(0.0, 1.0) var cloud_type := 0.8
## Metres between the highest ground and the clouds' base.
@export var base := 1200.0
## Metres from their base to their top.
@export var thickness := 2400.0
## The high ice cloud, 0 to 1.
@export_range(0.0, 1.0) var cirrus := 0.2
## Rain's clouds: grey all through, their sunlit sides gone dull.
@export_range(0.0, 1.0) var gloom := 0.0
## How much of the sun the clouds take off the ground.
@export_range(0.0, 1.0) var shade := 0.3

@export_group("Air")
## Haze over the low sky, 0 to 1, in `haze_color` (the fog's own colour).
@export_range(0.0, 1.0) var haze := 0.0
@export var haze_color := Color(0.62, 0.66, 0.7)
## The island's fog: its density times this, its start times `fog_near`.
@export var fog_density := 1.0
@export var fog_near := 1.0
## The light on the ground, times this.
@export_range(0.0, 2.0) var light := 1.0

@export_group("Wind and what falls")
## Metres a second, and the way it blows from (degrees, 0 north, 90 east).
@export var wind := 6.0
@export var wind_from := 250.0
@export_range(0.0, 1.0) var rain := 0.0
@export_range(0.0, 1.0) var snow := 0.0
## Strikes a minute.
@export var lightning := 0.0


## Every number as a dictionary, for blending.
func values() -> Dictionary:
	return {"coverage": coverage, "density": density, "cloud_type": cloud_type, "base": base,
		"thickness": thickness, "cirrus": cirrus, "gloom": gloom, "shade": shade, "haze": haze,
		"haze_color": haze_color, "fog_density": fog_density, "fog_near": fog_near, "light": light,
		"wind": wind, "wind_from": wind_from, "rain": rain, "snow": snow, "lightning": lightning}
