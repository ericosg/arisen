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
@onready var ui_level_label: Label = $UI/Level # Necromancer Level
@onready var ui_dark_energy_label: Label = $UI/DarkEnergy
@onready var ui_max_dark_energy_label: Label = $UI/MaxDarkEnergy
@onready var ui_mastery_points_label: Label = $UI/MasteryPoints # For MP
@onready var ui_log_label: RichTextLabel = $UI/Log # For Game Log

@onready var ui_level_up_button: Button = $UI/LevelUp # Necromancer Level Up Button
@onready var ui_reanimate_button: Button = $UI/Reanimate
@onready var ui_reanimate_type_button: Button = $UI/ReanimateType 
@onready var ui_soul_drain_button: Button = $UI/SoulDrain
@onready var ui_reanimate_upgrade_button: Button = $UI/ReanimateUpgrade
@onready var ui_soul_drain_upgrade_button: Button = $UI/SoulDrainUpgrade

@onready var ui_proceed_button: Button = $UI/GameStartButton 

@onready var ui_game_over_panel: Panel = $UI/GameOver
@onready var ui_game_over_status_label: Label = $UI/GameOver/Status
@onready var ui_game_over_restart_button: Button = $UI/GameOver/Restart

# --- UI PLACEHOLDERS ---
var ui_human_population_label: Label 
var ui_turn_wave_label: Label      

# --- Spell Instances (No longer loading from .tres) ---
var reanimate_spell_instance: SpellReanimateData
var soul_drain_spell_instance: SpellSoulDrainData

var current_reanimate_spell_level_selection = 1 # For UI cycling reanimate type selection

# --- Game Log ---
var game_log_messages: Array[String] = []
const MAX_LOG_LINES: int = 15 # Adjust as needed for your UI space


func _ready():
	ui_human_population_label = get_node_or_null("UI/HumanPopulationLabel") as Label 
	ui_turn_wave_label = get_node_or_null("UI/TurnWaveLabel") as Label 

	if not is_instance_valid(game_manager_node): printerr("Game.gd: GameManagerNode missing."); get_tree().quit(); return
	if not is_instance_valid(necromancer_node): printerr("Game.gd: NecromancerNode missing."); get_tree().quit(); return
	if not is_instance_valid(battle_grid_node): printerr("Game.gd: BattleGridNode missing."); get_tree().quit(); return
	if not is_instance_valid(units_container_node): printerr("Game.gd: UnitsContainerNode missing."); get_tree().quit(); return
	
	if is_instance_valid(ui_log_label):
		ui_log_label.bbcode_enabled = true # Enable BBCode for color parsing
	else:
		printerr("Game.gd: UI/Log Label node missing for game log.")

	# Initialize references
	game_manager_node.late_initialize_references(necromancer_node, battle_grid_node, units_container_node)
	necromancer_node.assign_runtime_references(game_manager_node, battle_grid_node) 

	# Create and learn spells
	reanimate_spell_instance = SpellReanimateData.new()
	necromancer_node.learn_spell(reanimate_spell_instance) 
	
	soul_drain_spell_instance = SpellSoulDrainData.new()
	necromancer_node.learn_spell(soul_drain_spell_instance) 

	_connect_game_signals()
	_log_message("Game Initialized. Necromancer awaits...", "white") 
	game_manager_node.start_new_game() 
	
	if is_instance_valid(ui_game_over_panel):
		ui_game_over_panel.visible = false
	
	# Initial UI updates
	_update_necromancer_labels_from_node() 
	_update_all_spell_related_ui()     
	_update_proceed_button_text()


func _connect_game_signals():
	if is_instance_valid(game_manager_node):
		if is_instance_valid(ui_human_population_label): 
			game_manager_node.human_population_changed.connect(_on_human_population_changed)
		if is_instance_valid(ui_turn_wave_label): 
			game_manager_node.turn_started.connect(_on_turn_or_wave_changed) 
			game_manager_node.wave_started.connect(_on_wave_started_log) 
		if is_instance_valid(ui_game_over_panel) and is_instance_valid(ui_game_over_status_label):
			game_manager_node.game_over.connect(_on_game_over) 
		
		game_manager_node.player_phase_started.connect(_on_player_phase_started)
		game_manager_node.battle_phase_started.connect(_on_battle_phase_started) 
		game_manager_node.wave_ended.connect(_on_wave_ended_log) 
		game_manager_node.turn_ended.connect(_on_turn_ended_log) 
		
		# Connect to GameManager's new signal for detailed event logging
		if game_manager_node.has_signal("game_event_log_requested"): # Check if signal exists
			game_manager_node.game_event_log_requested.connect(_on_game_manager_event_logged)
		else:
			printerr("Game.gd: GameManagerNode is missing 'game_event_log_requested' signal.")


	if is_instance_valid(necromancer_node):
		necromancer_node.de_changed.connect(_on_de_changed)
		necromancer_node.level_changed.connect(_on_level_changed) 
		necromancer_node.mastery_points_changed.connect(_on_mastery_points_changed) 
		necromancer_node.spell_upgraded.connect(_on_spell_upgraded) 
		necromancer_node.spell_cast_failed.connect(_on_spell_cast_failed_ui_log) 
		necromancer_node.spell_cast_succeeded.connect(_on_spell_cast_succeeded_ui_log)

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
	var bbcode_message = message
	var final_color_name = color_name.to_lower()

	# Ensure recognized colors, default to white
	match final_color_name:
		"green", "red", "yellow", "white":
			bbcode_message = "[color=%s]%s[/color]" % [final_color_name, message]
		_: # Unrecognized color string
			bbcode_message = "[color=white]%s[/color]" % message # Default to white
			# print_debug("Log: Unrecognized color '%s', defaulting to white for message: %s" % [color_name, message])
	
	# For console debugging, print the raw message without BBCode for readability
	if final_color_name == "red" and not message.begins_with("ERROR:"): # Avoid double "ERROR:"
		printerr("GAME LOG (UI: %s): %s" % [final_color_name, message])
	else:
		print("GAME LOG (UI: %s): %s" % [final_color_name, message])


	game_log_messages.append(bbcode_message) # Store the BBCode formatted message
	if game_log_messages.size() > MAX_LOG_LINES:
		game_log_messages.pop_front() # Remove the oldest message

	if is_instance_valid(ui_log_label):
		ui_log_label.text = "\n".join(game_log_messages)


func _on_game_manager_event_logged(message: String, color_tag: String):
	_log_message(message, color_tag)


func _on_spell_cast_failed_ui_log(spell_name: String, reason: String):
	_log_message("Cast %s failed: %s" % [spell_name, reason], "red")
	_update_all_spell_related_ui() 

func _on_spell_cast_succeeded_ui_log(spell_name: String):
	_log_message("%s cast successfully." % spell_name, "white") # Or green if preferred for success
	_update_all_spell_related_ui() 


# --- UI UPDATE & BUTTON HANDLER FUNCTIONS ---
func _update_necromancer_labels_from_node():
	if not is_instance_valid(necromancer_node): return
	if is_instance_valid(ui_level_label): ui_level_label.text = "Lvl: %d" % necromancer_node.level
	if is_instance_valid(ui_dark_energy_label): ui_dark_energy_label.text = "DE: %d" % necromancer_node.current_de 
	if is_instance_valid(ui_max_dark_energy_label): ui_max_dark_energy_label.text = "Max DE: %d" % necromancer_node.max_de 
	if is_instance_valid(ui_mastery_points_label): ui_mastery_points_label.text = "MP: %d" % necromancer_node.mastery_points

func _update_all_spell_related_ui():
	if not is_instance_valid(necromancer_node): return

	var reanimate_spell = necromancer_node.get_spell_by_name("Reanimate") 
	var soul_drain_spell = necromancer_node.get_spell_by_name("Soul Drain") 

	var can_act_in_phase = (game_manager_node.current_game_phase == GameManager.GamePhase.PLAYER_PRE_BATTLE or \
						   game_manager_node.current_game_phase == GameManager.GamePhase.PLAYER_POST_BATTLE)

	# Reanimate Button
	if is_instance_valid(ui_reanimate_button):
		if is_instance_valid(reanimate_spell):
			var current_de_cost = reanimate_spell.get_current_de_cost()
			ui_reanimate_button.text = "RNT L%d (%dDE)" % [reanimate_spell.spell_level, current_de_cost]
			ui_reanimate_button.disabled = not can_act_in_phase or necromancer_node.current_de < current_de_cost
		else: 
			ui_reanimate_button.text = "RNT (N/A)"
			ui_reanimate_button.disabled = true
	
	# Reanimate Upgrade Button
	if is_instance_valid(ui_reanimate_upgrade_button):
		if is_instance_valid(reanimate_spell):
			if reanimate_spell.spell_level < reanimate_spell.max_spell_level:
				var mp_cost = reanimate_spell.get_mastery_cost_for_next_upgrade()
				if mp_cost != -1:
					ui_reanimate_upgrade_button.text = "Up RNT L%d (%dMP)" % [reanimate_spell.spell_level + 1, mp_cost]
					ui_reanimate_upgrade_button.disabled = not can_act_in_phase or necromancer_node.mastery_points < mp_cost
				else: 
					ui_reanimate_upgrade_button.text = "Up RNT (Cost?)" 
					ui_reanimate_upgrade_button.disabled = true
			else:
				ui_reanimate_upgrade_button.text = "RNT MAX"
				ui_reanimate_upgrade_button.disabled = true
		else: 
			ui_reanimate_upgrade_button.text = "UP RNT (N/A)"
			ui_reanimate_upgrade_button.disabled = true

	# Soul Drain Button
	if is_instance_valid(ui_soul_drain_button):
		if is_instance_valid(soul_drain_spell):
			var current_de_cost = soul_drain_spell.get_current_de_cost()
			ui_soul_drain_button.text = "DRN L%d (%dDE)" % [soul_drain_spell.spell_level, current_de_cost]
			ui_soul_drain_button.disabled = not can_act_in_phase or necromancer_node.current_de < current_de_cost
		else:
			ui_soul_drain_button.text = "DRN (N/A)"
			ui_soul_drain_button.disabled = true

	# Soul Drain Upgrade Button
	if is_instance_valid(ui_soul_drain_upgrade_button):
		if is_instance_valid(soul_drain_spell):
			if soul_drain_spell.spell_level < soul_drain_spell.max_spell_level:
				var mp_cost = soul_drain_spell.get_mastery_cost_for_next_upgrade()
				if mp_cost != -1:
					ui_soul_drain_upgrade_button.text = "Up DRN L%d (%dMP)" % [soul_drain_spell.spell_level + 1, mp_cost]
					ui_soul_drain_upgrade_button.disabled = not can_act_in_phase or necromancer_node.mastery_points < mp_cost
				else:
					ui_soul_drain_upgrade_button.text = "Up DRN (Cost?)" 
					ui_soul_drain_upgrade_button.disabled = true
			else:
				ui_soul_drain_upgrade_button.text = "DRN MAX"
				ui_soul_drain_upgrade_button.disabled = true
		else:
			ui_soul_drain_upgrade_button.text = "UP DRN (N/A)"
			ui_soul_drain_upgrade_button.disabled = true
	
	_update_reanimate_type_button_text() 


func _on_human_population_changed(new_population: int):
	if is_instance_valid(ui_human_population_label):
		ui_human_population_label.text = "Humans: %d" % new_population
	_log_message("Human population changed to: %d" % new_population, "white")


func _on_de_changed(_current_de: int, _max_de: int): 
	_update_necromancer_labels_from_node() 
	_update_all_spell_related_ui() 

func _on_level_changed(new_level: int): # Necromancer level
	_update_necromancer_labels_from_node() 
	_update_all_spell_related_ui() 

func _on_mastery_points_changed(new_mastery_points: int):
	_update_necromancer_labels_from_node() 
	_update_all_spell_related_ui() 

func _on_turn_or_wave_changed(turn_number: int): 
	if is_instance_valid(ui_turn_wave_label) and is_instance_valid(game_manager_node):
		ui_turn_wave_label.text = "Turn: %d | Wave: %d" % [game_manager_node.current_turn, game_manager_node.current_wave_in_turn]
	_log_message("Turn %d started." % turn_number, "white")
	_update_proceed_button_text()
	_update_all_spell_related_ui() 

func _on_wave_started_log(wave_number: int, turn_number: int):
	_log_message("Wave %d of Turn %d begins." % [wave_number, turn_number], "white")
	if is_instance_valid(ui_turn_wave_label) and is_instance_valid(game_manager_node): 
		ui_turn_wave_label.text = "Turn: %d | Wave: %d" % [game_manager_node.current_turn, game_manager_node.current_wave_in_turn]
	_update_proceed_button_text()
	_update_all_spell_related_ui()


func _on_game_over(_reason_key: String, message: String): 
	if is_instance_valid(ui_game_over_panel) and is_instance_valid(ui_game_over_status_label):
		ui_game_over_status_label.text = "Game Over!\n%s" % message 
		ui_game_over_panel.visible = true
	if is_instance_valid(ui_proceed_button): ui_proceed_button.disabled = true
	_log_message("GAME OVER: %s" % message, "red")
	_update_all_spell_related_ui() 


func _on_player_phase_started(phase_name: String): 
	_log_message("Player Phase: %s" % phase_name, "white")
	_update_proceed_button_text()
	_update_all_spell_related_ui() 

func _on_battle_phase_started():
	_log_message("Battle Phase Started!", "yellow") # Changed to yellow
	_update_proceed_button_text()
	_update_all_spell_related_ui() 


func _on_wave_ended_log(wave_number: int, turn_number: int):
	_log_message("Wave %d of Turn %d ended." % [wave_number, turn_number], "white")
	_update_proceed_button_text()
	_update_all_spell_related_ui()

func _on_turn_ended_log(turn_number: int):
	_log_message("Turn %d ended." % turn_number, "white")
	if is_instance_valid(necromancer_node): 
		_log_message("Necromancer DE replenished to %d." % necromancer_node.max_de, "white")
	_update_proceed_button_text()
	_update_all_spell_related_ui()

func _on_spell_upgraded(spell_data: SpellData): 
	_log_message("%s upgraded to Lvl %d." % [spell_data.spell_name, spell_data.spell_level], "green") # Changed to green
	_update_all_spell_related_ui() 


func _on_level_up_button_pressed(): 
	if is_instance_valid(necromancer_node):
		var old_level = necromancer_node.level
		necromancer_node.level += 1 
		_log_message("Necromancer leveled up from Lvl %d to Lvl %d. MP +1." % [old_level, necromancer_node.level], "green") # Changed to green


func _on_reanimate_button_pressed():
	var reanimate_spell = necromancer_node.get_spell_by_name("Reanimate")
	if not is_instance_valid(reanimate_spell): 
		_log_message("Reanimate spell not found.", "red"); return

	var corpses = game_manager_node.get_available_corpses()
	if corpses.is_empty(): 
		_log_message("No corpses available to reanimate.", "yellow"); 
		return
	var target_corpse = corpses[0] 
	
	_log_message("Attempting to Reanimate corpse of %s..." % target_corpse.original_creature_name, "white")
	necromancer_node.attempt_cast_spell(reanimate_spell, target_corpse)


func _on_reanimate_type_button_pressed(): 
	current_reanimate_spell_level_selection += 1
	var reanimate_spell = necromancer_node.get_spell_by_name("Reanimate")
	var max_types = 3 
	if is_instance_valid(reanimate_spell):
		max_types = reanimate_spell.max_spell_level 
	
	if current_reanimate_spell_level_selection > max_types:
		current_reanimate_spell_level_selection = 1 
	_update_reanimate_type_button_text()
	_log_message("Reanimate type selection changed to: %s" % ui_reanimate_type_button.text, "white")


func _update_reanimate_type_button_text(): 
	if not is_instance_valid(ui_reanimate_type_button): return
	var type_str = "Skeleton" 
	
	match current_reanimate_spell_level_selection: 
		1: type_str = "Skeleton"
		2: type_str = "Zombie"
		3: type_str = "Spirit"
		_: type_str = "Unknown" 
	ui_reanimate_type_button.text = "Type: %s" % type_str


func _on_soul_drain_button_pressed():
	var soul_drain_spell = necromancer_node.get_spell_by_name("Soul Drain")
	if not is_instance_valid(soul_drain_spell): 
		_log_message("Soul Drain spell not found.", "red"); return

	var target_creature = null
	var target_info_for_log = "AoE"
	if soul_drain_spell._get_num_targets_for_level() == 1: 
		var potential_targets = game_manager_node.get_all_living_humans_and_aliens()
		if not potential_targets.is_empty(): 
			target_creature = potential_targets[0] 
			target_info_for_log = target_creature.creature_name
		else: 
			_log_message("No valid targets for single-target Soul Drain.", "yellow"); return
	
	_log_message("Attempting Soul Drain on %s..." % target_info_for_log, "white")
	necromancer_node.attempt_cast_spell(soul_drain_spell, target_creature)


func _on_reanimate_upgrade_button_pressed():
	if is_instance_valid(necromancer_node): 
		var spell = necromancer_node.get_spell_by_name("Reanimate")
		if is_instance_valid(spell):
			if spell.spell_level < spell.max_spell_level:
				var cost = spell.get_mastery_cost_for_next_upgrade()
				if cost != -1 and necromancer_node.mastery_points >= cost:
					_log_message("Attempting to upgrade Reanimate to Lvl %d for %d MP..." % [spell.spell_level + 1, cost], "white")
					if not necromancer_node.upgrade_spell_by_name("Reanimate"): 
						_log_message("Reanimate upgrade failed for an unknown reason.", "red") 
				elif cost != -1 : 
					_log_message("Not enough MP to upgrade Reanimate (needs %d MP)." % cost, "red")
			# else max level, button should be disabled
		else:
			_log_message("Reanimate spell not found for upgrade.", "red")


func _on_soul_drain_upgrade_button_pressed():
	if is_instance_valid(necromancer_node): 
		var spell = necromancer_node.get_spell_by_name("Soul Drain")
		if is_instance_valid(spell):
			if spell.spell_level < spell.max_spell_level:
				var cost = spell.get_mastery_cost_for_next_upgrade()
				if cost != -1 and necromancer_node.mastery_points >= cost:
					_log_message("Attempting to upgrade Soul Drain to Lvl %d for %d MP..." % [spell.spell_level + 1, cost], "white")
					if not necromancer_node.upgrade_spell_by_name("Soul Drain"):
						_log_message("Soul Drain upgrade failed for an unknown reason.", "red")
				elif cost != -1:
					_log_message("Not enough MP to upgrade Soul Drain (needs %d MP)." % cost, "red")
			# else max level
		else:
			_log_message("Soul Drain spell not found for upgrade.", "red")


func _on_proceed_button_pressed():
	if not is_instance_valid(game_manager_node): return
	var action_log = "Proceeding..."
	match game_manager_node.current_game_phase:
		GameManager.GamePhase.OUT_OF_TURN: action_log = "Starting Turn %d." % (game_manager_node.current_turn + 1)
		GameManager.GamePhase.PLAYER_PRE_BATTLE: action_log = "Starting Battle for Wave %d." % game_manager_node.current_wave_in_turn
		GameManager.GamePhase.PLAYER_POST_BATTLE: action_log = "Ending actions for Wave %d." % game_manager_node.current_wave_in_turn
		GameManager.GamePhase.WAVE_ENDING:
			if game_manager_node.current_wave_in_turn >= game_manager_node.max_waves_per_turn:
				action_log = "Ending Turn %d." % game_manager_node.current_turn 
			else:
				action_log = "Proceeding to next Wave (%d)." % (game_manager_node.current_wave_in_turn + 1)
		GameManager.GamePhase.TURN_ENDING: action_log = "Finalizing Turn %d." % game_manager_node.current_turn
	_log_message(action_log, "white")

	match game_manager_node.current_game_phase:
		GameManager.GamePhase.OUT_OF_TURN: game_manager_node.proceed_to_next_turn()
		GameManager.GamePhase.PLAYER_PRE_BATTLE: game_manager_node.player_ends_pre_battle_phase()
		GameManager.GamePhase.PLAYER_POST_BATTLE: game_manager_node.player_ends_post_battle_phase()
		GameManager.GamePhase.WAVE_ENDING: game_manager_node.proceed_to_next_wave()
		GameManager.GamePhase.TURN_ENDING: game_manager_node.proceed_to_next_turn()


func _update_proceed_button_text():
	if not is_instance_valid(ui_proceed_button) or not is_instance_valid(game_manager_node): return
	ui_proceed_button.disabled = false 
	match game_manager_node.current_game_phase:
		GameManager.GamePhase.OUT_OF_TURN: ui_proceed_button.text = "START TURN %d" % (game_manager_node.current_turn + 1)
		GameManager.GamePhase.TURN_STARTING: ui_proceed_button.text = "PREPARING..."; ui_proceed_button.disabled = true 
		GameManager.GamePhase.PLAYER_PRE_BATTLE: ui_proceed_button.text = "START BATTLE (W%d)" % game_manager_node.current_wave_in_turn
		GameManager.GamePhase.BATTLE_IN_PROGRESS: ui_proceed_button.text = "BATTLE..."; ui_proceed_button.disabled = true
		GameManager.GamePhase.PLAYER_POST_BATTLE: ui_proceed_button.text = "END WAVE %d ACTIONS" % game_manager_node.current_wave_in_turn
		GameManager.GamePhase.WAVE_ENDING:
			if game_manager_node.current_wave_in_turn >= game_manager_node.max_waves_per_turn:
				ui_proceed_button.text = "END TURN %d" % game_manager_node.current_turn 
			else:
				ui_proceed_button.text = "NEXT WAVE (%d)" % (game_manager_node.current_wave_in_turn + 1)
		GameManager.GamePhase.TURN_ENDING: ui_proceed_button.text = "ENDING TURN..."; ui_proceed_button.disabled = true 
		GameManager.GamePhase.NONE: ui_proceed_button.text = "GAME OVER"; ui_proceed_button.disabled = true
		_: ui_proceed_button.text = "PROCEED"; ui_proceed_button.disabled = true

func _on_restart_button_pressed():
	_log_message("Restarting game...", "white")
	get_tree().reload_current_scene()
