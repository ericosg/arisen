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
# We will create instances of these in _ready
var reanimate_spell_instance: SpellReanimateData
var soul_drain_spell_instance: SpellSoulDrainData

var current_reanimate_spell_level_selection = 1 # For UI cycling reanimate type selection


func _ready():
	ui_human_population_label = get_node_or_null("UI/HumanPopulationLabel") as Label 
	ui_turn_wave_label = get_node_or_null("UI/TurnWaveLabel") as Label 

	if not is_instance_valid(game_manager_node): printerr("Game.gd: GameManagerNode missing."); get_tree().quit(); return
	if not is_instance_valid(necromancer_node): printerr("Game.gd: NecromancerNode missing."); get_tree().quit(); return
	if not is_instance_valid(battle_grid_node): printerr("Game.gd: BattleGridNode missing."); get_tree().quit(); return
	if not is_instance_valid(units_container_node): printerr("Game.gd: UnitsContainerNode missing."); get_tree().quit(); return

	# Initialize references
	game_manager_node.late_initialize_references(necromancer_node, battle_grid_node, units_container_node)
	necromancer_node.assign_runtime_references(game_manager_node, battle_grid_node) 

	# Create and learn spells
	reanimate_spell_instance = SpellReanimateData.new()
	necromancer_node.learn_spell(reanimate_spell_instance) 
	
	soul_drain_spell_instance = SpellSoulDrainData.new()
	necromancer_node.learn_spell(soul_drain_spell_instance) 

	_connect_game_signals()
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
			game_manager_node.wave_started.connect(_on_turn_or_wave_changed)
		if is_instance_valid(ui_game_over_panel) and is_instance_valid(ui_game_over_status_label):
			game_manager_node.game_over.connect(_on_game_over)
		
		game_manager_node.player_phase_started.connect(_on_player_phase_started)
		game_manager_node.battle_phase_started.connect(_on_battle_phase_started)
		game_manager_node.wave_ended.connect(_on_wave_ended)
		game_manager_node.turn_ended.connect(_on_turn_ended)

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

# --- UI Log ---
func _log_message(message: String, is_error: bool = false):
	if is_error:
		printerr("GAME LOG (Error): %s" % message)
	else:
		print("GAME LOG: %s" % message)

func _on_spell_cast_failed_ui_log(spell_name: String, reason: String):
	_log_message("Failed to cast %s: %s" % [spell_name, reason], true)
	_update_all_spell_related_ui() # Refresh UI as DE might not have changed but state could

func _on_spell_cast_succeeded_ui_log(spell_name: String):
	_log_message("%s cast successfully." % spell_name)
	_update_all_spell_related_ui() # Refresh UI (e.g. DE changed)


# --- UI UPDATE & BUTTON HANDLER FUNCTIONS ---
func _update_necromancer_labels_from_node():
	if not is_instance_valid(necromancer_node): return
	if is_instance_valid(ui_level_label): ui_level_label.text = "Lvl: %d" % necromancer_node.level
	if is_instance_valid(ui_dark_energy_label): ui_dark_energy_label.text = str(necromancer_node.current_de)
	if is_instance_valid(ui_max_dark_energy_label): ui_max_dark_energy_label.text = str(necromancer_node.max_de)
	if is_instance_valid(ui_mastery_points_label): ui_mastery_points_label.text = "MP: %d" % necromancer_node.mastery_points

func _update_all_spell_related_ui():
	if not is_instance_valid(necromancer_node): return

	# Use the instances created in _ready
	var reanimate_spell = necromancer_node.get_spell_by_name("Reanimate") # Or use reanimate_spell_instance directly
	var soul_drain_spell = necromancer_node.get_spell_by_name("Soul Drain") # Or use soul_drain_spell_instance

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

func _on_de_changed(_current_de: int, _max_de: int): 
	if is_instance_valid(necromancer_node): 
		if is_instance_valid(ui_dark_energy_label): ui_dark_energy_label.text = str(necromancer_node.current_de)
		if is_instance_valid(ui_max_dark_energy_label): ui_max_dark_energy_label.text = str(necromancer_node.max_de)
	_update_all_spell_related_ui() 

func _on_level_changed(new_level: int): # Necromancer level
	if is_instance_valid(ui_level_label): ui_level_label.text = "Lvl: %d" % new_level
	_update_all_spell_related_ui() 

func _on_mastery_points_changed(new_mastery_points: int):
	if is_instance_valid(ui_mastery_points_label): ui_mastery_points_label.text = "MP: %d" % new_mastery_points
	_update_all_spell_related_ui() 

func _on_turn_or_wave_changed(_arg1 = null, _arg2 = null): 
	if is_instance_valid(ui_turn_wave_label) and is_instance_valid(game_manager_node):
		ui_turn_wave_label.text = "Turn: %d | Wave: %d" % [game_manager_node.current_turn, game_manager_node.current_wave_in_turn]
	_update_proceed_button_text()
	_update_all_spell_related_ui() 

func _on_game_over(_reason_key: String, message: String): 
	if is_instance_valid(ui_game_over_panel) and is_instance_valid(ui_game_over_status_label):
		ui_game_over_status_label.text = "Game Over!\n%s" % message 
		ui_game_over_panel.visible = true
	if is_instance_valid(ui_proceed_button): ui_proceed_button.disabled = true
	_update_all_spell_related_ui() # Disable spell buttons


func _on_player_phase_started(_phase_name: String): 
	_update_proceed_button_text()
	_update_all_spell_related_ui() 

func _on_battle_phase_started():
	_update_proceed_button_text()
	_update_all_spell_related_ui() 


func _on_wave_ended(_wave_num, _turn_num): 
	_update_proceed_button_text()
	_update_all_spell_related_ui()

func _on_turn_ended(_turn_num): 
	_update_proceed_button_text()
	_update_all_spell_related_ui()

func _on_spell_upgraded(_spell_data: SpellData): # A spell's level changed
	_update_all_spell_related_ui() 


func _on_level_up_button_pressed(): # Necromancer's main level
	if is_instance_valid(necromancer_node): 
		necromancer_node.level += 1 


func _on_reanimate_button_pressed():
	var reanimate_spell = necromancer_node.get_spell_by_name("Reanimate")
	if not is_instance_valid(reanimate_spell): 
		_log_message("Reanimate spell not found.", true); return

	var corpses = game_manager_node.get_available_corpses()
	if corpses.is_empty(): 
		_log_message("No corpses available to reanimate."); return
	var target_corpse = corpses[0] 
	
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

func _update_reanimate_type_button_text(): 
	if not is_instance_valid(ui_reanimate_type_button): return
	var type_str = "Skeleton" 
	# var reanimate_spell = necromancer_node.get_spell_by_name("Reanimate") # Not strictly needed for this UI logic

	match current_reanimate_spell_level_selection: # This selection is for UI display
		1: type_str = "Skeleton"
		2: type_str = "Zombie"
		3: type_str = "Spirit"
		_: type_str = "Unknown" 
	ui_reanimate_type_button.text = "Type: %s" % type_str


func _on_soul_drain_button_pressed():
	var soul_drain_spell = necromancer_node.get_spell_by_name("Soul Drain")
	if not is_instance_valid(soul_drain_spell): 
		_log_message("Soul Drain spell not found.", true); return

	var target_creature = null
	if soul_drain_spell._get_num_targets_for_level() == 1: 
		var potential_targets = game_manager_node.get_all_living_humans_and_aliens()
		if not potential_targets.is_empty(): 
			target_creature = potential_targets[0] 
		else: 
			_log_message("No valid targets for single-target Soul Drain."); return
	necromancer_node.attempt_cast_spell(soul_drain_spell, target_creature)


func _on_reanimate_upgrade_button_pressed():
	if is_instance_valid(necromancer_node): 
		if not necromancer_node.upgrade_spell_by_name("Reanimate"):
			var spell = necromancer_node.get_spell_by_name("Reanimate")
			if is_instance_valid(spell) and spell.spell_level < spell.max_spell_level:
				var cost = spell.get_mastery_cost_for_next_upgrade()
				if cost != -1 and necromancer_node.mastery_points < cost:
					_log_message("Not enough MP to upgrade Reanimate.", true)

func _on_soul_drain_upgrade_button_pressed():
	if is_instance_valid(necromancer_node): 
		if not necromancer_node.upgrade_spell_by_name("Soul Drain"):
			var spell = necromancer_node.get_spell_by_name("Soul Drain")
			if is_instance_valid(spell) and spell.spell_level < spell.max_spell_level:
				var cost = spell.get_mastery_cost_for_next_upgrade()
				if cost != -1 and necromancer_node.mastery_points < cost:
					_log_message("Not enough MP to upgrade Soul Drain.", true)


func _on_proceed_button_pressed():
	if not is_instance_valid(game_manager_node): return
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
	get_tree().reload_current_scene()
