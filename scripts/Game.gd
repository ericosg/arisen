# ./scripts/Game.gd
extends Node 

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
@onready var ui_mastery_points_label: Label = $UI/MasteryPoints 
@onready var ui_log_label: RichTextLabel = $UI/Log 

@onready var ui_level_up_button: Button = $UI/LevelUp 
@onready var ui_reanimate_button: Button = $UI/Reanimate
@onready var ui_reanimate_type_button: Button = $UI/ReanimateType 
@onready var ui_soul_drain_button: Button = $UI/SoulDrain
@onready var ui_reanimate_upgrade_button: Button = $UI/ReanimateUpgrade
@onready var ui_soul_drain_upgrade_button: Button = $UI/SoulDrainUpgrade

@onready var ui_proceed_button: Button = $UI/GameStartButton # This is the main progression button

@onready var ui_game_over_panel: Panel = $UI/GameOver
@onready var ui_game_over_status_label: Label = $UI/GameOver/Status
@onready var ui_game_over_restart_button: Button = $UI/GameOver/Restart
 
@onready var ui_human_population_label: Label = $UI/HumanPopulationLabel
@onready var ui_turn_wave_label: Label = $UI/TurnWaveLabel     

# --- Spell Instances ---
var reanimate_spell_instance: SpellReanimateData
var soul_drain_spell_instance: SpellSoulDrainData

# Index for ReanimateSubtype enum (0:Skel, 1:Zom, 2:Spirit)
var current_reanimate_subtype_selection_index: int = 0 

# --- Game Log ---
var game_log_messages: Array[String] = []
const MAX_LOG_LINES: int = 20 


func _ready():
	# Ensure all critical node references are valid, otherwise quit.
	if not is_instance_valid(game_manager_node): printerr("Game.gd: GameManagerNode missing."); get_tree().quit(); return
	if not is_instance_valid(necromancer_node): printerr("Game.gd: NecromancerNode missing."); get_tree().quit(); return
	if not is_instance_valid(battle_grid_node): printerr("Game.gd: BattleGridNode missing."); get_tree().quit(); return
	if not is_instance_valid(units_container_node): printerr("Game.gd: UnitsContainerNode missing."); get_tree().quit(); return
	
	if is_instance_valid(ui_log_label):
		ui_log_label.bbcode_enabled = true # Enable rich text formatting for colors
	else:
		printerr("Game.gd: UI/Log Label node missing for game log.")

	# Initialize core game components with necessary references
	game_manager_node.late_initialize_references(necromancer_node, battle_grid_node, units_container_node)
	necromancer_node.assign_runtime_references(game_manager_node, battle_grid_node) 

	# Create and learn spells for the Necromancer
	reanimate_spell_instance = SpellReanimateData.new()
	necromancer_node.learn_spell(reanimate_spell_instance) 
	
	soul_drain_spell_instance = SpellSoulDrainData.new()
	necromancer_node.learn_spell(soul_drain_spell_instance) 

	_connect_game_signals() # Connect signals between game components and UI
	_log_message("Game Initialized. Necromancer awaits...", "white") 
	game_manager_node.start_new_game() # Start the game logic
	
	if is_instance_valid(ui_game_over_panel):
		ui_game_over_panel.visible = false # Hide game over panel initially
	
	# Initial UI updates
	_update_necromancer_labels_from_node() 
	_update_all_spell_related_ui()     
	# _update_proceed_button_ui() will be called by player_phase_started("OUT_OF_TURN") from start_new_game()


func _connect_game_signals():
	# Connect signals from GameManager to UI update functions
	if is_instance_valid(game_manager_node):
		game_manager_node.human_population_changed.connect(_on_human_population_changed)
		game_manager_node.turn_started.connect(_on_turn_started_ui_update) 
		game_manager_node.wave_started.connect(_on_wave_started_ui_update) 
		game_manager_node.game_over.connect(_on_game_over) 
		
		game_manager_node.player_phase_started.connect(_on_player_phase_started_ui_update)
		game_manager_node.battle_phase_started.connect(_on_battle_phase_started_ui_update) 
		game_manager_node.wave_ended.connect(_on_wave_ended_ui_update) 
		game_manager_node.turn_finalized.connect(_on_turn_finalized_ui_update) 
		
		if game_manager_node.has_signal("game_event_log_requested"): 
			game_manager_node.game_event_log_requested.connect(_on_game_manager_event_logged)
		else:
			printerr("Game.gd: GameManagerNode is missing 'game_event_log_requested' signal.")

	# Connect signals from Necromancer to UI update functions
	if is_instance_valid(necromancer_node):
		necromancer_node.de_changed.connect(_on_de_changed)
		necromancer_node.level_changed.connect(_on_level_changed) 
		necromancer_node.mastery_points_changed.connect(_on_mastery_points_changed) 
		necromancer_node.spell_upgraded.connect(_on_spell_upgraded) 
		necromancer_node.spell_cast_failed.connect(_on_spell_cast_failed_ui_log) 
		necromancer_node.spell_cast_succeeded.connect(_on_spell_cast_succeeded_ui_log)

	# Connect UI button press signals to their handler functions
	if is_instance_valid(ui_level_up_button): ui_level_up_button.pressed.connect(_on_level_up_button_pressed) 
	if is_instance_valid(ui_reanimate_button): ui_reanimate_button.pressed.connect(_on_reanimate_button_pressed)
	if is_instance_valid(ui_reanimate_type_button): ui_reanimate_type_button.pressed.connect(_on_reanimate_type_button_pressed)
	if is_instance_valid(ui_soul_drain_button): ui_soul_drain_button.pressed.connect(_on_soul_drain_button_pressed)
	if is_instance_valid(ui_reanimate_upgrade_button): ui_reanimate_upgrade_button.pressed.connect(_on_reanimate_upgrade_button_pressed)
	if is_instance_valid(ui_soul_drain_upgrade_button): ui_soul_drain_upgrade_button.pressed.connect(_on_soul_drain_upgrade_button_pressed)
	if is_instance_valid(ui_proceed_button): ui_proceed_button.pressed.connect(_on_proceed_button_pressed)
	if is_instance_valid(ui_game_over_restart_button): ui_game_over_restart_button.pressed.connect(_on_restart_button_pressed)

# --- Game Log Management ---
func _log_message(message: String, color_name: String = "white"):
	"""Adds a message to the in-game log with specified color."""
	var bbcode_message = message
	var final_color_name = color_name.to_lower()
	# Apply color tags for RichTextLabel
	match final_color_name:
		"green", "red", "yellow", "white", "gray", "orange": 
			bbcode_message = "[color=%s]%s[/color]" % [final_color_name, message]
		_: # Default to white if color is not recognized
			bbcode_message = "[color=white]%s[/color]" % message 
	
	# Also print errors to the Godot console for easier debugging
	if final_color_name == "red" and not message.begins_with("ERROR:"): # Avoid double "ERROR:"
		printerr("GAME LOG (UI: %s): %s" % [final_color_name, message])
	# else: print("GAME LOG (UI: %s): %s" % [final_color_name, message]) # Optional: print all logs to console

	game_log_messages.append(bbcode_message) 
	# Keep the log from growing indefinitely
	if game_log_messages.size() > MAX_LOG_LINES: 
		game_log_messages.pop_front() 
	
	if is_instance_valid(ui_log_label): 
		ui_log_label.text = "\n".join(game_log_messages) # Display messages separated by newlines

func _on_game_manager_event_logged(message: String, color_tag: String):
	"""Handles generic log requests from GameManager."""
	_log_message(message, color_tag)

func _on_spell_cast_failed_ui_log(spell_name: String, reason: String):
	"""Logs spell cast failures and updates spell UI."""
	_log_message("Cast %s failed: %s" % [spell_name, reason], "red")
	_update_all_spell_related_ui() 

func _on_spell_cast_succeeded_ui_log(spell_name: String):
	"""Logs spell cast successes and updates spell UI."""
	_log_message("%s cast successfully." % spell_name, "green") 
	_update_all_spell_related_ui() 

# --- UI UPDATE & BUTTON HANDLER FUNCTIONS ---
func _update_necromancer_labels_from_node():
	"""Updates UI labels related to Necromancer stats."""
	if not is_instance_valid(necromancer_node): return
	if is_instance_valid(ui_level_label): ui_level_label.text = "Lvl: %d" % necromancer_node.level
	if is_instance_valid(ui_dark_energy_label): ui_dark_energy_label.text = "DE: %d" % necromancer_node.current_de 
	if is_instance_valid(ui_max_dark_energy_label): ui_max_dark_energy_label.text = "Max DE: %d" % necromancer_node.max_de 
	if is_instance_valid(ui_mastery_points_label): ui_mastery_points_label.text = "MP: %d" % necromancer_node.mastery_points

func _update_all_spell_related_ui():
	"""Updates all UI elements related to spells (buttons, costs, availability)."""
	if not is_instance_valid(necromancer_node) or not is_instance_valid(game_manager_node): return

	var reanimate_spell = necromancer_node.get_spell_by_name("Reanimate") as SpellReanimateData
	var soul_drain_spell = necromancer_node.get_spell_by_name("Soul Drain") as SpellSoulDrainData

	var current_gm_phase = game_manager_node.current_game_phase
	# Define in which game phases spells can be cast
	# MODIFIED: Removed OUT_OF_TURN from can_cast_in_phase
	var can_cast_in_phase = (
		current_gm_phase == GameManager.GamePhase.PLAYER_PRE_BATTLE or \
		current_gm_phase == GameManager.GamePhase.PLAYER_POST_BATTLE or \
		current_gm_phase == GameManager.GamePhase.TURN_AWAITING_FIRST_WAVE or \
		current_gm_phase == GameManager.GamePhase.WAVE_CONCLUDED_AWAITING_NEXT or \
		current_gm_phase == GameManager.GamePhase.TURN_ENDING_AWAIT_CONFIRM
	)
	# Define in which game phases spells can be upgraded
	var can_upgrade_in_phase = (
		current_gm_phase == GameManager.GamePhase.OUT_OF_TURN or \
		current_gm_phase == GameManager.GamePhase.TURN_AWAITING_FIRST_WAVE or \
		current_gm_phase == GameManager.GamePhase.PLAYER_POST_BATTLE or \
		current_gm_phase == GameManager.GamePhase.WAVE_CONCLUDED_AWAITING_NEXT or \
		current_gm_phase == GameManager.GamePhase.TURN_ENDING_AWAIT_CONFIRM
	)

	# Update Reanimate spell UI
	if is_instance_valid(ui_reanimate_button) and is_instance_valid(ui_reanimate_type_button):
		if is_instance_valid(reanimate_spell):
			var selected_subtype_enum = reanimate_spell.get_subtype_enum_from_index(current_reanimate_subtype_selection_index)
			var subtype_name = reanimate_spell.get_subtype_name_from_enum(selected_subtype_enum)
			ui_reanimate_type_button.text = "Type: %s" % subtype_name

			var de_cost_for_selected_subtype = reanimate_spell.get_current_de_cost(selected_subtype_enum)
			var subtype_unlocked = reanimate_spell.spell_level >= reanimate_spell.subtype_unlock_level.get(selected_subtype_enum, 99)

			if de_cost_for_selected_subtype != -1 and subtype_unlocked:
				ui_reanimate_button.text = "RNT %s (%dDE)" % [subtype_name.substr(0,3).to_upper(), de_cost_for_selected_subtype]
				ui_reanimate_button.disabled = not can_cast_in_phase or necromancer_node.current_de < de_cost_for_selected_subtype
			else: 
				ui_reanimate_button.text = "RNT %s (Lck)" % subtype_name.substr(0,3).to_upper()
				ui_reanimate_button.disabled = true
		else: 
			ui_reanimate_button.text = "RNT (N/A)"; ui_reanimate_button.disabled = true
			ui_reanimate_type_button.text = "Type: (N/A)"
	
	# Update Reanimate upgrade button UI
	if is_instance_valid(ui_reanimate_upgrade_button):
		if is_instance_valid(reanimate_spell):
			if reanimate_spell.spell_level < reanimate_spell.max_spell_level:
				var mp_cost = reanimate_spell.get_mastery_cost_for_next_upgrade()
				if mp_cost != -1:
					ui_reanimate_upgrade_button.text = "Up RNT L%d (%dMP)" % [reanimate_spell.spell_level + 1, mp_cost]
					ui_reanimate_upgrade_button.disabled = not can_upgrade_in_phase or necromancer_node.mastery_points < mp_cost
				else: 
					ui_reanimate_upgrade_button.text = "Up RNT (Cost?)"; ui_reanimate_upgrade_button.disabled = true
			else:
				ui_reanimate_upgrade_button.text = "RNT MAX"; ui_reanimate_upgrade_button.disabled = true
		else: 
			ui_reanimate_upgrade_button.text = "UP RNT (N/A)"; ui_reanimate_upgrade_button.disabled = true

	# Update Soul Drain spell UI
	if is_instance_valid(ui_soul_drain_button):
		if is_instance_valid(soul_drain_spell):
			var current_de_cost = soul_drain_spell.get_current_de_cost()
			ui_soul_drain_button.text = "DRN L%d (%dDE)" % [soul_drain_spell.spell_level, current_de_cost]
			ui_soul_drain_button.disabled = not can_cast_in_phase or necromancer_node.current_de < current_de_cost
		else:
			ui_soul_drain_button.text = "DRN (N/A)"; ui_soul_drain_button.disabled = true

	# Update Soul Drain upgrade button UI
	if is_instance_valid(ui_soul_drain_upgrade_button):
		if is_instance_valid(soul_drain_spell):
			if soul_drain_spell.spell_level < soul_drain_spell.max_spell_level:
				var mp_cost = soul_drain_spell.get_mastery_cost_for_next_upgrade()
				if mp_cost != -1:
					ui_soul_drain_upgrade_button.text = "Up DRN L%d (%dMP)" % [soul_drain_spell.spell_level + 1, mp_cost]
					ui_soul_drain_upgrade_button.disabled = not can_upgrade_in_phase or necromancer_node.mastery_points < mp_cost
				else:
					ui_soul_drain_upgrade_button.text = "Up DRN (Cost?)"; ui_soul_drain_upgrade_button.disabled = true
			else:
				ui_soul_drain_upgrade_button.text = "DRN MAX"; ui_soul_drain_upgrade_button.disabled = true
		else:
			ui_soul_drain_upgrade_button.text = "UP DRN (N/A)"; ui_soul_drain_upgrade_button.disabled = true
	
# --- Signal Handlers for Game State Changes ---
func _on_human_population_changed(new_population: int):
	if is_instance_valid(ui_human_population_label): ui_human_population_label.text = "Humans: %d" % new_population

func _on_de_changed(_current_de: int, _max_de: int): 
	_update_necromancer_labels_from_node(); _update_all_spell_related_ui() 
func _on_level_changed(_new_level: int): 
	_update_necromancer_labels_from_node(); _update_all_spell_related_ui() 
func _on_mastery_points_changed(_new_mastery_points: int):
	_update_necromancer_labels_from_node(); _update_all_spell_related_ui() 

func _update_turn_wave_label():
	"""Updates the turn and wave display label based on the current game state."""
	if not is_instance_valid(ui_turn_wave_label) or not is_instance_valid(game_manager_node): return
	
	var gm = game_manager_node
	match gm.current_game_phase:
		GameManager.GamePhase.OUT_OF_TURN:
			if gm.current_turn == 0 : ui_turn_wave_label.text = "Prepare for Turn 1"
			else: ui_turn_wave_label.text = "Turn %d Complete" % gm.current_turn
		GameManager.GamePhase.TURN_AWAITING_FIRST_WAVE:
			ui_turn_wave_label.text = "Turn: %d | Prep Wave 1" % gm.current_turn
		GameManager.GamePhase.PLAYER_PRE_BATTLE, \
		GameManager.GamePhase.BATTLE_IN_PROGRESS, \
		GameManager.GamePhase.PLAYER_POST_BATTLE:
			ui_turn_wave_label.text = "Turn: %d | Wave: %d" % [gm.current_turn, gm.current_wave_in_turn]
		GameManager.GamePhase.WAVE_CONCLUDED_AWAITING_NEXT:
			ui_turn_wave_label.text = "Turn: %d | Wave %d Done" % [gm.current_turn, gm.current_wave_in_turn]
		GameManager.GamePhase.TURN_ENDING_AWAIT_CONFIRM:
			ui_turn_wave_label.text = "Turn: %d | All Waves Done" % gm.current_turn
		_: # Default for internal phases like TURN_STARTING, TURN_ENDING, or NONE
			ui_turn_wave_label.text = "Turn: %d | Wave: %d" % [gm.current_turn, gm.current_wave_in_turn]


func _on_turn_started_ui_update(turn_number: int): 
	_log_message("Turn %d setup complete. Human reinforcements deployed." % turn_number, "white")
	_update_turn_wave_label()
	# Further UI updates (buttons, spells) are driven by player_phase_started("TURN_AWAITING_FIRST_WAVE")

func _on_wave_started_ui_update(wave_number: int, turn_number: int):
	_log_message("Wave %d of Turn %d begins. Aliens inbound!" % [wave_number, turn_number], "yellow")
	_update_turn_wave_label()
	# Further UI updates driven by player_phase_started("PRE_BATTLE")

func _on_game_over(_reason_key: String, message: String): 
	if is_instance_valid(ui_game_over_panel) and is_instance_valid(ui_game_over_status_label):
		ui_game_over_status_label.text = "Game Over!\n%s" % message 
		ui_game_over_panel.visible = true
	if is_instance_valid(ui_proceed_button): ui_proceed_button.disabled = true
	_log_message("GAME OVER: %s" % message, "red"); 
	_update_all_spell_related_ui() 
	if is_instance_valid(ui_level_up_button): ui_level_up_button.disabled = true


func _on_player_phase_started_ui_update(phase_name_string: String): 
	"""Central handler for UI updates when a new player-actionable phase begins."""
	_log_message("Player action phase: %s" % phase_name_string, "gray")
	_update_turn_wave_label() 
	_update_proceed_button_ui() # This now also handles the Necromancer level up button
	_update_all_spell_related_ui() 

func _on_battle_phase_started_ui_update():
	_log_message("Battle Phase Started for Wave %d!" % game_manager_node.current_wave_in_turn, "orange") 
	_update_turn_wave_label()
	_update_proceed_button_ui(); _update_all_spell_related_ui() 

func _on_wave_ended_ui_update(wave_number: int, turn_number: int):
	"""Handles the end of wave processing, primarily for logging."""
	_log_message("Wave %d of Turn %d processing complete." % [wave_number, turn_number], "white")
	_update_turn_wave_label()
	# Subsequent UI updates are driven by player_phase_started signals for WAVE_CONCLUDED_AWAITING_NEXT or TURN_ENDING_AWAIT_CONFIRM

func _on_turn_finalized_ui_update(turn_number: int): 
	_log_message("Turn %d finalized." % turn_number, "white")
	_update_turn_wave_label()
	# Subsequent UI updates are driven by player_phase_started("OUT_OF_TURN")

func _on_spell_upgraded(spell_data: SpellData): 
	_log_message("%s upgraded to Lvl %d." % [spell_data.spell_name, spell_data.spell_level], "green") 
	_update_all_spell_related_ui() 

# --- Button Press Handlers ---
func _on_level_up_button_pressed(): 
	if is_instance_valid(necromancer_node):
		var old_level = necromancer_node.level 
		necromancer_node.level_up_player() # Necromancer script handles level and MP increment
		# Log success/failure based on actual level change, as level_up_player might have conditions in future
		if necromancer_node.level > old_level:
			_log_message("Necromancer leveled up from Lvl %d to Lvl %d. MP +1." % [old_level, necromancer_node.level], "green")
		# else: # Optional: Log if level up failed (e.g., if there was a cost not met)
			# _log_message("Necromancer level up attempt failed.", "yellow")


func _on_reanimate_button_pressed():
	var reanimate_spell = necromancer_node.get_spell_by_name("Reanimate") as SpellReanimateData
	if not is_instance_valid(reanimate_spell): 
		_log_message("Reanimate spell not found.", "red"); return

	var corpses = game_manager_node.get_available_corpses()
	if corpses.is_empty(): 
		_log_message("No corpses available to reanimate.", "yellow"); return
	var target_corpse = corpses[0] # Simple targeting: first available corpse
	
	var selected_subtype_enum = reanimate_spell.get_subtype_enum_from_index(current_reanimate_subtype_selection_index)
	var subtype_name = reanimate_spell.get_subtype_name_from_enum(selected_subtype_enum)
	
	_log_message("Attempting to Reanimate %s from corpse of %s..." % [subtype_name, target_corpse.original_creature_name], "white")
	necromancer_node.attempt_cast_spell(reanimate_spell, target_corpse, selected_subtype_enum)

func _on_reanimate_type_button_pressed(): 
	current_reanimate_subtype_selection_index = (current_reanimate_subtype_selection_index + 1) % 3 # Cycle 0,1,2
	_update_all_spell_related_ui() # Update button text and disabled states
	
	# Log the change for clarity
	var reanimate_spell = necromancer_node.get_spell_by_name("Reanimate") as SpellReanimateData
	if is_instance_valid(reanimate_spell):
		var selected_subtype_enum = reanimate_spell.get_subtype_enum_from_index(current_reanimate_subtype_selection_index)
		var subtype_name = reanimate_spell.get_subtype_name_from_enum(selected_subtype_enum)
		_log_message("Reanimate type selection changed to: %s" % subtype_name, "white")

func _on_soul_drain_button_pressed():
	var soul_drain_spell = necromancer_node.get_spell_by_name("Soul Drain") as SpellSoulDrainData
	if not is_instance_valid(soul_drain_spell): 
		_log_message("Soul Drain spell not found.", "red"); return

	var target_creature = null
	var target_info_for_log = "AoE" # Default for multi-target spells
	if soul_drain_spell._get_num_targets_for_level() == 1: # If spell is single-target at current level
		var potential_targets = game_manager_node.get_all_living_humans_and_aliens()
		if not potential_targets.is_empty(): 
			target_creature = potential_targets[0] # Simple targeting: first available
			target_info_for_log = target_creature.creature_name
		else: 
			_log_message("No valid targets for single-target Soul Drain.", "yellow"); return
	
	_log_message("Attempting Soul Drain on %s..." % target_info_for_log, "white")
	necromancer_node.attempt_cast_spell(soul_drain_spell, target_creature, null) # Pass null for spell_specific_arg

func _on_reanimate_upgrade_button_pressed():
	if is_instance_valid(necromancer_node): 
		necromancer_node.upgrade_spell_by_name("Reanimate") # Necromancer handles logging success/fail

func _on_soul_drain_upgrade_button_pressed():
	if is_instance_valid(necromancer_node): 
		necromancer_node.upgrade_spell_by_name("Soul Drain") # Necromancer handles logging

func _on_proceed_button_pressed():
	"""Handles the main progression button click based on the current game phase."""
	if not is_instance_valid(game_manager_node): return
	
	var current_phase = game_manager_node.current_game_phase
	# print_debug("Proceed button pressed. Current Phase: %s" % GameManager.GamePhase.keys()[current_phase]) # For debugging

	match current_phase:
		GameManager.GamePhase.OUT_OF_TURN:
			game_manager_node.player_starts_new_turn()
		GameManager.GamePhase.TURN_AWAITING_FIRST_WAVE:
			game_manager_node.player_starts_wave()
		GameManager.GamePhase.PLAYER_PRE_BATTLE:
			game_manager_node.player_ends_pre_battle_phase()
		GameManager.GamePhase.PLAYER_POST_BATTLE:
			game_manager_node.player_ends_post_battle_phase()
		GameManager.GamePhase.WAVE_CONCLUDED_AWAITING_NEXT:
			game_manager_node.player_starts_wave()
		GameManager.GamePhase.TURN_ENDING_AWAIT_CONFIRM:
			game_manager_node.player_confirms_end_turn()
		_:
			_log_message("Proceed button pressed in unhandled phase: %s" % GameManager.GamePhase.keys()[current_phase], "red")

func _update_proceed_button_ui():
	"""Updates the text and disabled state of the main progression button and Necromancer level up button."""
	if not is_instance_valid(ui_proceed_button) or not is_instance_valid(game_manager_node): return
	
	ui_proceed_button.disabled = false # Default to enabled
	var current_phase = game_manager_node.current_game_phase
	var gm = game_manager_node # Alias for brevity

	# Handle Necromancer Level Up button state
	if is_instance_valid(ui_level_up_button):
		# Enable level up only when out of turn (between turns)
		ui_level_up_button.disabled = (current_phase != GameManager.GamePhase.OUT_OF_TURN)
		# Future: Add cost check, e.g., or necromancer_node.xp < necromancer_node.xp_to_next_level

	match current_phase:
		GameManager.GamePhase.OUT_OF_TURN:
			ui_proceed_button.text = "START TURN %d" % (gm.current_turn + 1)
		GameManager.GamePhase.TURN_STARTING: # Internal processing phase
			ui_proceed_button.text = "PREPARING TURN..."; ui_proceed_button.disabled = true 
		GameManager.GamePhase.TURN_AWAITING_FIRST_WAVE:
			ui_proceed_button.text = "START WAVE 1"
		GameManager.GamePhase.PLAYER_PRE_BATTLE:
			ui_proceed_button.text = "START BATTLE (W%d)" % gm.current_wave_in_turn
		GameManager.GamePhase.BATTLE_IN_PROGRESS: # Internal processing phase
			ui_proceed_button.text = "BATTLE IN PROGRESS..."; ui_proceed_button.disabled = true
		GameManager.GamePhase.PLAYER_POST_BATTLE:
			ui_proceed_button.text = "END WAVE %d ACTIONS" % gm.current_wave_in_turn
		GameManager.GamePhase.WAVE_CONCLUDED_AWAITING_NEXT:
			ui_proceed_button.text = "START WAVE %d" % (gm.current_wave_in_turn + 1)
		GameManager.GamePhase.TURN_ENDING_AWAIT_CONFIRM:
			ui_proceed_button.text = "END TURN %d" % gm.current_turn
		GameManager.GamePhase.TURN_ENDING: # Internal processing phase
			ui_proceed_button.text = "ENDING TURN..."; ui_proceed_button.disabled = true 
		GameManager.GamePhase.NONE: # Game Over
			ui_proceed_button.text = "GAME OVER"; ui_proceed_button.disabled = true
		_: # Should not happen with defined phases
			ui_proceed_button.text = "PROCEED (?)"; ui_proceed_button.disabled = true

func _on_restart_button_pressed():
	_log_message("Restarting game...", "white")
	get_tree().reload_current_scene()
