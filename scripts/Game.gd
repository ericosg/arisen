# Game.gd
extends Node

@onready var game_start: Button = $UI/GameStart

func _on_game_start_pressed() -> void:
	game_start.visible = false
	var game_manager = get_node("/root/GameManager")
	game_manager.start_game()
