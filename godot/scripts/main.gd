## MEWD — the root: the picture's layers, top to bottom, and the game
## in the buffer at the bottom of them.
##
##   the HUD           a CanvasLayer, not filtered
##   the lo-fi filter  Lofi's TextureRect over its SubViewport
##   the world         the Game, a Node3D inside that SubViewport
extends Node

var lofi: Lofi
var game: Node3D

func _ready() -> void:
	lofi = Lofi.new()
	add_child(lofi)
	game = preload("res://godot/scripts/game/game.gd").new()
	game.name = "Game"
	lofi.world.add_child(game)

func _unhandled_input(event: InputEvent) -> void:
	game.handle_input(event)
