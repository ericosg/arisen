# ./scripts/Game.gd
extends Node # Or Node2D if your game root has a 2D presence

# This script is typically attached to the root node of your main game scene (e.g., Game.tscn).
# It's responsible for setting up the main components and handling global UI connections.

# --- CORE NODE REFERENCES ---
@onready var game_manager_node: GameManager = $GameManagerNode 
@onready var necromancer_node: Necromancer = $NecromancerNode
@onready var battle_grid_node: BattleGrid = $BattleGridNode
@onready var units_container_node: Node2D = $UnitsContainerNode

# --- UI NODE REFERENCES (Match names in your Game.tscn) ---
@onready var ui_level_label: Label = $UI/Level
@onready var ui_dark_energy_label: Label = $UI/DarkEnergy
@onready var ui_max_dark_energy_label: Label = $UI/MaxDarkEnergy
@onready var ui_mastery_points_label: Label = $UI/MasteryPoints # Assuming this will be used

@onready var ui_level_up_button: Button = $UI/LevelUp
@onready var ui_reanimate_button: Button = $UI/Reanimate
@onready var ui_reanimate_type_button: Button = $UI/ReanimateType
@onready var ui_soul_drain_button: Button = $UI/SoulDrain
@onready var ui_reanimate_upgrade_button: Button = $UI/ReanimateUpgrade
@onready var ui_soul_drain_upgrade_button: Button = $UI/SoulDrainUpgrade

# This button's function might change based on game state.
# For now, let's assume it's a general "Proceed" or "Next Step" button.
# The GameStartButton is very prominent, so it might be used to initiate turns/waves.
@onready var ui_proceed_button: Button = $UI/GameStartButton # Renamed for clarity in code

@onready var ui_game_over_panel: Panel = $UI/GameOver
@onready var ui_game_over_status_label: Label = $UI/GameOver/Status
@onready var ui_game_over_restart_button: Button = $UI/GameOver/Restart

# --- Additional UI (Not in your scene yet, but from GameManager signals) ---
# You'll need to add these to your Game.tscn if you want to display them.
# @onready var ui_human_population_label: Label = $UI/HumanPopulationLabel 
# @onready var ui_turn_wave_label: Label = $UI/TurnWaveLabel


# --- Spell Data (Load these resources) ---
# Ensure these .tres files exist and are correctly configured SpellData resources.
var reanimate_spell_resource: SpellReanimateData = load("res://scripts/spells/SpellReanimateData.tres")
var soul_drain_spell_resource: SpellSoulDrainData = load("res://scripts/spells/SpellSoulDrainData.tres")
# Add other spell resources here

# Temp state for reanimate type selection
var current_reanimate_spell_level_selection = 1 # Default to Skeleton (Level 1 of Reanimate spell)


func _ready():
	# Ensure all critical node references are valid
	if not is_instance_valid(game_manager_node):
		printerr("Game.gd: GameManagerNode not found or invalid. Game cannot start.")
		get_tree().quit(); return
	if not is_instance_valid(necromancer_node):
		printerr("Game.gd: NecromancerNode not found or invalid. Game cannot start.")
		get_tree().quit(); return
	if not is_instance_valid(battle_grid_node):
		printerr("Game.gd: BattleGridNode not found or invalid. Game cannot start.")
		get_tree().quit(); return
	if not is_instance_valid(units_container_node):
		printerr("Game.gd: UnitsContainerNode not found or invalid. Game cannot start.")
		get_tree().quit(); return

	# Provide GameManager with its necessary dependencies
	game_manager_node.late_initialize_references(necromancer_node, battle_grid_node, units_container_node)

	# Learn initial spells (ensure .tres files are created for these spells)
	if is_instance_valid(reanimate_spell_resource):
		necromancer_node.learn_spell(reanimate_spell_resource.duplicate(true)) # Duplicate to get a unique instance
	else:
		printerr("Game.gd: Failed to load Reanimate spell resource.")
	
	if is_instance_valid(soul_drain_spell_resource):
		necromancer_node.learn_spell(soul_drain_spell_resource.duplicate(true)) # Duplicate
	else:
		printerr("Game.gd: Failed to load Soul Drain spell resource.")

	# Connect signals from GameManager and Necromancer to UI update functions
	_connect_game_signals()

	# Start the game logic
	game_manager_node.start_new_game() # This will set initial GamePhase
	
	# Initially hide game over panel
	if is_instance_valid(ui_game_over_panel):
		ui_game_over_panel.visible = false
	
	# Update UI button text/state based on initial game phase
	_update_proceed_button_text()
	_update_reanimate_type_button_text()


func _connect_game_signals():
	# --- Connect GameManager Signals to UI & Game Logic ---
	if is_instance_valid(game_manager_node):
		game_manager_node.human_population_changed.connect(_on_human_population_changed)
		game_manager_node.turn_started.connect(_on_turn_or_wave_changed)
		game_manager_node.wave_started.connect(_on_turn_or_wave_changed)
		game_manager_node.game_over.connect(_on_game_over)
		game_manager_node.player_phase_started.connect(_on_player_phase_started)
		game_manager_node.battle_phase_started.connect(_on_battle_phase_started)
		game_manager_node.wave_ended.connect(_on_wave_ended)
		game_manager_node.turn_ended.connect(_on_turn_ended)

	# --- Connect Necromancer Signals to UI ---
	if is_instance_valid(necromancer_node):
		necromancer_node.de_changed.connect(_on_de_changed)
		necromancer_node.level_changed.connect(_on_level_changed)
		# Mastery points might need its own signal if it's a separate resource
		# necromancer_node.mastery_points_changed.connect(_on_mastery_points_changed)
		necromancer_node.spell_upgraded.connect(_on_spell_upgraded)


	# --- Connect UI Button Presses ---
	if is_instance_valid(ui_level_up_button):
		ui_level_up_button.pressed.connect(_on_level_up_button_pressed)
	if is_instance_valid(ui_reanimate_button):
		ui_reanimate_button.pressed.connect(_on_reanimate_button_pressed)
	if is_instance_valid(ui_reanimate_type_button):
		ui_reanimate_type_button.pressed.connect(_on_reanimate_type_button_pressed)
	if is_instance_valid(ui_soul_drain_button):
		ui_soul_drain_button.pressed.connect(_on_soul_drain_button_pressed)
	if is_instance_valid(ui_reanimate_upgrade_button):
		ui_reanimate_upgrade_button.pressed.connect(_on_reanimate_upgrade_button_pressed)
	if is_instance_valid(ui_soul_drain_upgrade_button):
		ui_soul_drain_upgrade_button.pressed.connect(_on_soul_drain_upgrade_button_pressed)
	if is_instance_valid(ui_proceed_button):
		ui_proceed_button.pressed.connect(_on_proceed_button_pressed)
	if is_instance_valid(ui_game_over_restart_button):
		ui_game_over_restart_button.pressed.connect(_on_restart_button_pressed)


# --- UI UPDATE & BUTTON HANDLER FUNCTIONS ---

func _on_human_population_changed(new_population: int):
	# if is_instance_valid(ui_human_population_label):
	#     ui_human_population_label.text = "Humans: %d" % new_population
	print_debug("UI Update: Human Population = %d" % new_population) # Placeholder

func _on_de_changed(current_de: int, max_de: int):
	if is_instance_valid(ui_dark_energy_label):
		ui_dark_energy_label.text = str(current_de)
	if is_instance_valid(ui_max_dark_energy_label):
		ui_max_dark_energy_label.text = str(max_de)

func _on_level_changed(new_level: int):
	if is_instance_valid(ui_level_label):
		ui_level_label.text = "Lvl: %d" % new_level # Changed to include "Lvl: "
	# Update Mastery Points if they are tied to level
	if is_instance_valid(ui_mastery_points_label):
		ui_mastery_points_label.text = "MP: %d" % new_level # Example: 1 mastery point per level

func _on_mastery_points_changed(points: int): # Placeholder if you add this signal
	if is_instance_valid(ui_mastery_points_label):
		ui_mastery_points_label.text = "MP: %d" % points

func _on_turn_or_wave_changed():
	# if is_instance_valid(ui_turn_wave_label) and is_instance_valid(game_manager_node):
	#    ui_turn_wave_label.text = "Turn: %d | Wave: %d" % [game_manager_node.current_turn, game_manager_node.current_wave_in_turn]
	print_debug("UI Update: Turn %d, Wave %d" % [game_manager_node.current_turn, game_manager_node.current_wave_in_turn]) # Placeholder
	_update_proceed_button_text()

func _on_game_over(reason_key: String, message: String):
	if is_instance_valid(ui_game_over_panel) and is_instance_valid(ui_game_over_status_label):
		ui_game_over_status_label.text = "Game Over!\n%s" % message # Removed reason_key for brevity
		ui_game_over_panel.visible = true
	# Disable other UI interaction buttons
	ui_proceed_button.disabled = true
	# ... disable other buttons ...

func _on_player_phase_started(phase_name: String):
	# print_debug("Player phase started: %s" % phase_name)
	_update_proceed_button_text()
	# Enable/disable spell buttons based on phase
	var can_cast_spells = (phase_name == "PRE_BATTLE" or phase_name == "POST_BATTLE_REANIMATE")
	ui_reanimate_button.disabled = not can_cast_spells
	ui_soul_drain_button.disabled = not can_cast_spells
	# Other UI updates based on phase

func _on_battle_phase_started():
	# print_debug("Battle phase started.")
	_update_proceed_button_text()
	# Disable spell casting buttons during battle
	ui_reanimate_button.disabled = true
	ui_soul_drain_button.disabled = true

func _on_wave_ended(_wave_num, _turn_num):
	# print_debug("Wave ended.")
	_update_proceed_button_text()
	# Re-enable spell casting if moving to post-battle phase (handled by _on_player_phase_started)

func _on_turn_ended(_turn_num):
	# print_debug("Turn ended.")
	_update_proceed_button_text()

func _on_spell_upgraded(spell_data: SpellData):
	# print_debug("UI: Spell %s upgraded to level %d" % [spell_data.spell_name, spell_data.spell_level])
	# Potentially update UI elements related to specific spells if they show level or cost
	if spell_data.spell_name == "Reanimate":
		_update_reanimate_type_button_text() # Cost might have changed
		# Check if max level reached for upgrade button
		if is_instance_valid(ui_reanimate_upgrade_button):
			ui_reanimate_upgrade_button.disabled = (spell_data.spell_level >= spell_data.max_spell_level)
	elif spell_data.spell_name == "Soul Drain":
		if is_instance_valid(ui_soul_drain_upgrade_button):
			ui_soul_drain_upgrade_button.disabled = (spell_data.spell_level >= spell_data.max_spell_level)


# --- BUTTON PRESS HANDLERS ---
func _on_level_up_button_pressed():
	# print_debug("Level Up MC button pressed.")
	# This needs a method in Necromancer or GameManager to handle the actual leveling logic
	# For example, if leveling up costs something or is only allowed at certain times.
	# necromancer_node.attempt_mc_level_up() # Assuming such a method exists
	if is_instance_valid(necromancer_node): # Simple direct level up for now
		necromancer_node.level += 1 # This will trigger the _set_level and emit signal
		# Add logic for spending mastery points if that's the mechanic
		print_debug("Necromancer manually leveled up to %d via UI button." % necromancer_node.level)


func _on_reanimate_button_pressed():
	# print_debug("Reanimate button pressed. Selected type level: %d" % current_reanimate_spell_level_selection)
	var reanimate_spell = necromancer_node.get_spell_by_name("Reanimate")
	if not is_instance_valid(reanimate_spell):
		printerr("Game.gd: Reanimate spell not found in Necromancer's known spells.")
		return

	# Temporarily set the spell's level to the player's selection for this cast
	# This assumes the player has "unlocked" this level of the spell by upgrading it.
	# A better way would be to have separate SpellData resources for each level, or
	# the spell itself handles which effect to use based on its *actual* upgraded level.
	# For now, we'll use the selected level to determine type, but cast with spell's actual level.
	# The SpellReanimateData.gd already uses its internal 'spell_level' to determine type.
	# So, we just need to ensure the spell is upgraded to the desired level.
	
	# TODO: Implement target selection for corpses
	# For now, try to reanimate the first available corpse
	var corpses = game_manager_node.get_available_corpses()
	if corpses.is_empty():
		print_debug("No corpses available to reanimate.")
		# Optionally show a message to the player via UI
		return
		
	var target_corpse = corpses[0] # Select the first one for testing
	
	# Ensure the reanimate spell is at a level that can summon the type implied by current_reanimate_spell_level_selection
	if reanimate_spell.spell_level < current_reanimate_spell_level_selection:
		print_debug("Reanimate spell (Lvl %d) is not high enough to summon selected type (needs Lvl %d)." % [reanimate_spell.spell_level, current_reanimate_spell_level_selection])
		# Show UI message: "Upgrade Reanimate spell to summon this type."
		return

	# The SpellReanimateData's apply_effect will use its *actual* spell_level to determine type.
	# The current_reanimate_spell_level_selection is more of a UI hint for the player for which *effect* they want,
	# assuming the base spell has been upgraded enough.
	# For simplicity now, we assume the Reanimate button tries to cast at the spell's current learned level.
	# The ReanimateType button just cycles what the player *wishes* to get if the spell is high enough.
	
	necromancer_node.attempt_cast_spell(reanimate_spell, target_corpse)


func _on_reanimate_type_button_pressed():
	current_reanimate_spell_level_selection += 1
	var reanimate_spell = necromancer_node.get_spell_by_name("Reanimate")
	var max_level_for_type_selection = 3 # Skeleton, Zombie, Spirit
	if is_instance_valid(reanimate_spell):
		# Max selection should not exceed the spell's actual max level for types
		max_level_for_type_selection = reanimate_spell.max_spell_level 
		
	if current_reanimate_spell_level_selection > max_level_for_type_selection: # Cycle through 1, 2, 3
		current_reanimate_spell_level_selection = 1
	_update_reanimate_type_button_text()

func _update_reanimate_type_button_text():
	if not is_instance_valid(ui_reanimate_type_button): return
	var type_str = "Skeleton"
	if current_reanimate_spell_level_selection == 2: type_str = "Zombie"
	elif current_reanimate_spell_level_selection == 3: type_str = "Spirit"
	ui_reanimate_type_button.text = "Type: %s" % type_str


func _on_soul_drain_button_pressed():
	# print_debug("Soul Drain button pressed.")
	var soul_drain_spell = necromancer_node.get_spell_by_name("Soul Drain")
	if not is_instance_valid(soul_drain_spell):
		printerr("Game.gd: Soul Drain spell not found.")
		return

	# TODO: Implement target selection for Soul Drain if it's single target (level 1)
	var target_creature = null
	if soul_drain_spell._get_num_targets_for_level() == 1: # Assuming helper exists
		# Find a valid target - e.g., first living alien or human
		var potential_targets = game_manager_node.get_all_living_humans_and_aliens()
		if not potential_targets.is_empty():
			target_creature = potential_targets[0] # Select first for testing
		else:
			print_debug("No valid targets for single-target Soul Drain.")
			return
			
	necromancer_node.attempt_cast_spell(soul_drain_spell, target_creature)


func _on_reanimate_upgrade_button_pressed():
	# print_debug("Reanimate Upgrade button pressed.")
	if is_instance_valid(necromancer_node):
		necromancer_node.upgrade_spell_by_name("Reanimate")

func _on_soul_drain_upgrade_button_pressed():
	# print_debug("Soul Drain Upgrade button pressed.")
	if is_instance_valid(necromancer_node):
		necromancer_node.upgrade_spell_by_name("Soul Drain")

func _on_proceed_button_pressed():
	# This button's action depends on the current game phase
	if not is_instance_valid(game_manager_node): return
	
	match game_manager_node.current_game_phase:
		GameManager.GamePhase.OUT_OF_TURN:
			game_manager_node.proceed_to_next_turn()
		GameManager.GamePhase.PLAYER_PRE_BATTLE:
			game_manager_node.player_ends_pre_battle_phase() # This is "Start Battle"
		GameManager.GamePhase.PLAYER_POST_BATTLE:
			game_manager_node.player_ends_post_battle_phase() # This is "End Wave Reanimation / Proceed"
		GameManager.GamePhase.WAVE_ENDING: # After wave ends, player clicks to start next wave setup
			game_manager_node.proceed_to_next_wave()
		GameManager.GamePhase.TURN_ENDING: # Should automatically go to OUT_OF_TURN or player clicks to start next
			game_manager_node.proceed_to_next_turn() # Or a different button text like "End Turn Summary"
		_:
			print_debug("Proceed button pressed in unhandled phase: %s" % GameManager.GamePhase.keys()[game_manager_node.current_game_phase])
	_update_proceed_button_text()


func _update_proceed_button_text():
	if not is_instance_valid(ui_proceed_button) or not is_instance_valid(game_manager_node):
		return

	ui_proceed_button.disabled = false # Enable by default, disable if no action
	match game_manager_node.current_game_phase:
		GameManager.GamePhase.OUT_OF_TURN:
			ui_proceed_button.text = "START TURN %d" % (game_manager_node.current_turn + 1)
		GameManager.GamePhase.TURN_STARTING: # Auto-transitions usually
			ui_proceed_button.text = "PREPARING..."
			ui_proceed_button.disabled = true 
		GameManager.GamePhase.PLAYER_PRE_BATTLE:
			ui_proceed_button.text = "START BATTLE (Wave %d)" % game_manager_node.current_wave_in_turn
		GameManager.GamePhase.BATTLE_IN_PROGRESS:
			ui_proceed_button.text = "BATTLE..."
			ui_proceed_button.disabled = true
		GameManager.GamePhase.PLAYER_POST_BATTLE:
			ui_proceed_button.text = "END WAVE %d ACTIONS" % game_manager_node.current_wave_in_turn
		GameManager.GamePhase.WAVE_ENDING:
			if game_manager_node.current_wave_in_turn >= game_manager_node.max_waves_per_turn:
				ui_proceed_button.text = "END TURN %d" % game_manager_node.current_turn # Will trigger turn end logic
			else:
				ui_proceed_button.text = "NEXT WAVE (%d)" % (game_manager_node.current_wave_in_turn + 1)
		GameManager.GamePhase.TURN_ENDING:
			ui_proceed_button.text = "PROCESSING TURN END..."
			ui_proceed_button.disabled = true # Auto-transitions to OUT_OF_TURN
		GameManager.GamePhase.NONE: # Game Over
			ui_proceed_button.text = "GAME OVER"
			ui_proceed_button.disabled = true
		_:
			ui_proceed_button.text = "PROCEED"
			ui_proceed_button.disabled = true


func _on_restart_button_pressed():
	# print_debug("Restart button pressed.")
	get_tree().reload_current_scene()
