# ./scripts/Game.gd
extends Node # Or Node2D if your game root has a 2D presence

# This script is typically attached to the root node of your main game scene (e.g., Game.tscn).
# It's responsible for setting up the main components and potentially handling global UI connections.

# --- NODE REFERENCES (Set these up in the Godot Editor by dragging nodes here or using @onready) ---
# Ensure these paths match your actual scene tree structure in Game.tscn.
@onready var game_manager_node: GameManager = $GameManagerNode 
# Assuming "GameManagerNode" is the name of the Node with GameManager.gd attached.

@onready var necromancer_node: Necromancer = $NecromancerNode
# Assuming "NecromancerNode" is the name of the Node with Necromancer.gd attached.

@onready var battle_grid_node: BattleGrid = $BattleGridNode
# Assuming "BattleGridNode" is the name of the Node2D with BattleGrid.gd attached.

@onready var units_container_node: Node2D = $UnitsContainerNode
# Assuming "UnitsContainerNode" is a Node2D used as a parent for all creature visuals.

# --- UI NODE REFERENCES (Examples - adjust to your actual UI scene structure) ---
# @onready var next_turn_button: Button = $UI/ControlContainer/NextTurnButton
# @onready var next_wave_button: Button = $UI/ControlContainer/NextWaveButton
# @onready var start_battle_button: Button = $UI/ControlContainer/StartBattleButton
# @onready var end_post_battle_phase_button: Button = $UI/ControlContainer/EndPostBattlePhaseButton
# @onready var human_population_label: Label = $UI/StatsDisplay/HumanPopulationLabel
# @onready var de_label: Label = $UI/StatsDisplay/DELabel
# @onready var turn_wave_label: Label = $UI/StatsDisplay/TurnWaveLabel
# @onready var game_over_panel: Panel = $UI/GameOverPanel
# @onready var game_over_message_label: Label = $UI/GameOverPanel/MessageLabel


func _ready():
	# Ensure all critical node references are valid
	if not is_instance_valid(game_manager_node):
		printerr("Game.gd: GameManagerNode not found or invalid. Game cannot start.")
		get_tree().quit() # Critical error, exit game
		return
	if not is_instance_valid(necromancer_node):
		printerr("Game.gd: NecromancerNode not found or invalid. Game cannot start.")
		get_tree().quit()
		return
	if not is_instance_valid(battle_grid_node):
		printerr("Game.gd: BattleGridNode not found or invalid. Game cannot start.")
		get_tree().quit()
		return
	if not is_instance_valid(units_container_node):
		printerr("Game.gd: UnitsContainerNode not found or invalid. Game cannot start.")
		get_tree().quit()
		return

	# print_debug("Game.gd: All main nodes referenced successfully.")

	# Provide GameManager with its necessary dependencies
	game_manager_node.late_initialize_references(necromancer_node, battle_grid_node, units_container_node)

	# Connect signals from GameManager and Necromancer to UI update functions
	_connect_game_signals()

	# Start the game logic
	game_manager_node.start_new_game()
	
	# Initially hide game over panel if it exists
	# if is_instance_valid(game_over_panel):
	#     game_over_panel.visible = false
	
	# print_debug("Game.gd: Initialization complete. Game started via GameManager.")


func _connect_game_signals():
	# --- Connect GameManager Signals to UI ---
	if is_instance_valid(game_manager_node):
		# Example connections (uncomment and adapt if UI nodes are ready):
		# if is_instance_valid(human_population_label):
		#     game_manager_node.human_population_changed.connect(_on_human_population_changed)
		# if is_instance_valid(turn_wave_label):
		#     game_manager_node.turn_started.connect(_on_turn_or_wave_changed)
		#     game_manager_node.wave_started.connect(_on_turn_or_wave_changed)
		# if is_instance_valid(game_over_panel) and is_instance_valid(game_over_message_label):
		#     game_manager_node.game_over.connect(_on_game_over)
		
		# Connect UI Button presses to GameManager actions
		# if is_instance_valid(next_turn_button):
		#     next_turn_button.pressed.connect(game_manager_node.proceed_to_next_turn)
		# if is_instance_valid(next_wave_button):
		#     next_wave_button.pressed.connect(game_manager_node.proceed_to_next_wave)
		# if is_instance_valid(start_battle_button):
		#     start_battle_button.pressed.connect(game_manager_node.player_ends_pre_battle_phase)
		# if is_instance_valid(end_post_battle_phase_button):
		#     end_post_battle_phase_button.pressed.connect(game_manager_node.player_ends_post_battle_phase)
		pass # Add more connections as your UI develops

	# --- Connect Necromancer Signals to UI ---
	if is_instance_valid(necromancer_node):
		# Example connections:
		# if is_instance_valid(de_label):
		#     necromancer_node.de_changed.connect(_on_de_changed)
		pass # Add more connections


# --- UI UPDATE FUNCTIONS (Called by signals) ---
# These are examples. Implement them based on your UI nodes.

# func _on_human_population_changed(new_population: int):
#    if is_instance_valid(human_population_label):
#        human_population_label.text = "Humans: %d" % new_population

# func _on_de_changed(current_de: int, max_de: int):
#    if is_instance_valid(de_label):
#        de_label.text = "DE: %d/%d" % [current_de, max_de]

# func _on_turn_or_wave_changed():
#    if is_instance_valid(turn_wave_label) and is_instance_valid(game_manager_node):
#        turn_wave_label.text = "Turn: %d | Wave: %d" % [game_manager_node.current_turn, game_manager_node.current_wave_in_turn]

# func _on_game_over(reason_key: String, message: String):
#    if is_instance_valid(game_over_panel) and is_instance_valid(game_over_message_label):
#        game_over_message_label.text = "Game Over!\n%s\n(%s)" % [message, reason_key]
#        game_over_panel.visible = true
	# Disable game input, show restart button, etc.


# --- INPUT HANDLING (Example for global keys, if any) ---
# func _unhandled_input(event: InputEvent):
#    if event.is_action_pressed("ui_cancel"): # Escape key
#        # Potentially open a pause menu or quit
#        get_tree().quit() 
#    if event.is_action_pressed("debug_next_turn") and is_instance_valid(game_manager_node):
#        if game_manager_node.current_game_phase == GameManager.GamePhase.OUT_OF_TURN or \
#           game_manager_node.current_game_phase == GameManager.GamePhase.TURN_ENDING:
#            game_manager_node.proceed_to_next_turn()
#        elif game_manager_node.current_game_phase == GameManager.GamePhase.PLAYER_PRE_BATTLE:
#             game_manager_node.player_ends_pre_battle_phase()
#        elif game_manager_node.current_game_phase == GameManager.GamePhase.PLAYER_POST_BATTLE:
#             game_manager_node.player_ends_post_battle_phase()
#        elif game_manager_node.current_game_phase == GameManager.GamePhase.WAVE_ENDING:
#             game_manager_node.proceed_to_next_wave()


# --- SCENE SETUP NOTES ---
# In your Game.tscn:
# RootNode (with Game.gd attached)
#  L GameManagerNode (Node with GameManager.gd)
#  L NecromancerNode (Node with Necromancer.gd)
#  L BattleGridNode (Node2D with BattleGrid.gd)
#  L UnitsContainerNode (Node2D to hold all creature visuals)
#  L UI (CanvasLayer or Control node for all UI elements)
#      L ControlContainer (VBoxContainer, HBoxContainer, etc. for buttons)
#          L NextTurnButton (Button)
#          L NextWaveButton (Button)
#          ...etc.
#      L StatsDisplay
#          L HumanPopulationLabel (Label)
#          L DELabel (Label)
#          ...etc.
#      L GameOverPanel (Panel)
#          L MessageLabel (Label)
