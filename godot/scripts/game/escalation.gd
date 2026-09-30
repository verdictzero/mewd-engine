## MEWD — who the night brings, and what they come in (the parts of
## js/game.js and js/main.js that hold js/responders.js, js/brigade.js,
## js/water.js and js/vehicles.js together).
##
## ONE NODE FOR THE GAME TO OWN: the fleet (every vehicle, drawn as its
## children) and the SWAT and the army (Responders). Add it to the Game,
## tic it once a tic, draw it once a frame. (The fire brigade and its
## water cannon went with the fire that spread, at the user's request.)
##
## THE MODELS are the user's GLBs, loaded the first time a force asks
## for one (see model()): the police van for the SWAT, the hover APC for
## the army, and the panel van for the car park. A force whose model is not there simply does not come — the
## same bargain every other asset in this game makes.
class_name Escalation
extends Node3D

## which file each force's vehicle is, and how long it is — js/main.js
const MODELS := {
	"police": {"url": "res://assets/models/police_assault.glb", "length": VehicleModel.POLICE_LENGTH, "id": "police", "name": "Assault van", "use": "police"},
	"apc": {"url": "res://assets/models/apc.glb", "length": VehicleModel.APC_LENGTH, "id": "apc", "name": "Hover APC", "use": "army"},
	"van": {"url": "res://assets/models/van.glb", "length": VehicleModel.VAN_LENGTH, "id": "van", "name": "Van", "use": "civil"},
}

var game
var vehicles: Vehicles
var responders: Responders
var _models := {}

func _init(g) -> void:
	game = g
	name = "Escalation"
	vehicles = Vehicles.new(g)
	add_child(vehicles)
	responders = Responders.new(g, vehicles, model)
	# the car park, where the map has one (level carSlots)
	var slots = responders.map_value("carSlots")
	if slots is Array and not slots.is_empty():
		vehicles.place(slots, model("van"))

## The model one force arrives in, loaded on first asking; null if the
## file is not there.
func model(key: String) -> VehicleModel:
	if not _models.has(key):
		var m: Dictionary = MODELS.get(key, {})
		_models[key] = VehicleModel.load_glb(m.url, m) if not m.is_empty() else null
	return _models[key]

## One tic: the vehicles, then who is coming.
func tic() -> void:
	vehicles.tic()
	responders.tic()

## Once a frame: nothing yet. (The vehicles are nodes and draw
## themselves; the light bars flash on the shader's own clock.)
func draw() -> void:
	pass
