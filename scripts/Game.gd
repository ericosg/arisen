# Game.gd (Main scene script)
extends Node

# Assuming UI is structured under a CanvasLayer named UI, child of this Game node.
@onready var game_start_button: Button = $UI/GameStartButton 
@onready var game_over_panel: Panel = $UI/GameOver
@onready var game_over_text: Label = $UI/GameOver/Status
@onready var restart_button: Button = $UI/GameOver/Restart
@onready var game_manager: GameManager = $GameManager

func _ready() -> void:
	if not game_manager:
		printerr("Game scene: GameManager not found!")
		return

	if is_instance_valid(game_start_button):
		game_start_button.connect("pressed", Callable(self, "_on_game_start_pressed"))
	else:
		push_warning("GameStartButton not found in UI.")
		# If no start button, maybe start game directly for testing
		# _on_game_start_pressed() 

	if is_instance_valid(restart_button):
		restart_button.connect("pressed", Callable(self, "_on_restart_button_pressed"))
	else:
		push_warning("RestartButton not found in GameOverPanel.")
		
	if is_instance_valid(game_over_panel):
		game_over_panel.visible = false # Hide game over panel initially
	else:
		push_warning("GameOverPanel not found in UI.")

	# Connect to GameManager signals for game over
	# Assuming GameManager has a 'game_ended_signal(player_won_flag)'
	# For now, direct call from GameManager.game_over() is fine if it accesses UI here.
	# Let's adjust GameManager to emit a signal that this Game.gd can catch.
	# Add to GameManager: signal game_is_over(player_won_flag)
	# game_manager.connect("game_is_over", Callable(self, "show_game_over_screen"))


func _on_game_start_pressed() -> void:
	if is_instance_valid(game_start_button):
		game_start_button.visible = false
	if is_instance_valid(game_over_panel):
		game_over_panel.visible = false # Ensure it's hidden

	if game_manager:
		game_manager.start_game()
	else:
		printerr("Cannot start game: GameManager not available.")


func _on_restart_button_pressed() -> void:
	if is_instance_valid(game_over_panel):
		game_over_panel.visible = false
	# Option 1: Reload current scene
	# get_tree().reload_current_scene()
	# Option 2: Call start_game again (ensure proper reset in start_game)
	if game_manager:
		game_manager.start_game() # GameManager.start_game needs to fully reset state
	else:
		printerr("Cannot restart game: GameManager not available.")


# This function would be called by GameManager's game_is_over signal
func show_game_over_screen(player_won: bool) -> void:
	if not is_instance_valid(game_over_panel) or not is_instance_valid(game_over_text):
		printerr("GameOverPanel or StatusLabel not found. Cannot display game over.")
		return
		
	game_over_panel.visible = true
	if player_won:
		game_over_text.text = "VICTORY!\nEarth is safe... for now."
	else:
		game_over_text.text = "DEFEAT!\nThe swarm has consumed Earth."
