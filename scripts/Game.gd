# ./scripts/Game.gd
extends Node # Or Node2D if your game root has a 2D presence

# This script is typically attached to the root node of your main game scene (e.g., Game.tscn).
# It's responsible for setting up the main components and potentially handling global UI connections.

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

@onready var ui_level_up_button: Button = $UI/LevelUp
@onready var ui_reanimate_button: Button = $UI/Reanimate
@onready var ui_reanimate_type_button: Button = $UI/ReanimateType
@onready var ui_soul_drain_button: Button = $UI/SoulDrain
@onready var ui_reanimate_upgrade_button: Button = $UI/ReanimateUpgrade
@onready var ui_soul_drain_upgrade_button: Button = $UI/SoulDrainUpgrade

@onready var ui_proceed_button: Button = $UI/GameStartButton 

@onready var ui_game_over_panel: Panel = $UI/GameOver
@onready var ui_game_over_status_label: Label = $UI/GameOver/Status
@onready var ui_game_over_restart_button: Button = $UI/GameOver/Restart

# --- UI PLACEHOLDERS (Add these to your Game.tscn UI if you want to use them) ---
# You'll need to create these Label nodes in your UI section in Game.tscn
var ui_human_population_label: Label # Example: $UI/StatsDisplay/HumanPopulationLabel
var ui_turn_wave_label: Label      # Example: $UI/StatsDisplay/TurnWaveLabel


# --- Spell Data (Load these resources) ---
var reanimate_spell_resource: SpellReanimateData = load("res://scripts/spells/SpellReanimateData.tres")
var soul_drain_spell_resource: SpellSoulDrainData = load("res://scripts/spells/SpellSoulDrainData.tres")

var current_reanimate_spell_level_selection = 1 


func _ready():
	# Assign UI placeholders if they exist in the scene
	ui_human_population_label = get_node_or_null("UI/HumanPopulationLabel") as Label # Adjust path as needed
	ui_turn_wave_label = get_node_or_null("UI/TurnWaveLabel") as Label # Adjust path as needed


	if not is_instance_valid(game_manager_node): printerr("Game.gd: GameManagerNode missing."); get_tree().quit(); return
	if not is_instance_valid(necromancer_node): printerr("Game.gd: NecromancerNode missing."); get_tree().quit(); return
	if not is_instance_valid(battle_grid_node): printerr("Game.gd: BattleGridNode missing."); get_tree().quit(); return
	if not is_instance_valid(units_container_node): printerr("Game.gd: UnitsContainerNode missing."); get_tree().quit(); return

	game_manager_node.late_initialize_references(necromancer_node, battle_grid_node, units_container_node)

	if is_instance_valid(reanimate_spell_resource):
		necromancer_node.learn_spell(reanimate_spell_resource.duplicate(true)) 
	else:
		printerr("Game.gd: Failed to load Reanimate spell resource. Ensure 'res://scripts/spells/SpellReanimateData.tres' exists.")
	
	if is_instance_valid(soul_drain_spell_resource):
		necromancer_node.learn_spell(soul_drain_spell_resource.duplicate(true)) 
	else:
		printerr("Game.gd: Failed to load Soul Drain spell resource. Ensure 'res://scripts/spells/SpellSoulDrainData.tres' exists.")

	_connect_game_signals()
	game_manager_node.start_new_game() 
	
	if is_instance_valid(ui_game_over_panel):
		ui_game_over_panel.visible = false
	
	_update_proceed_button_text()
	_update_reanimate_type_button_text()


func _connect_game_signals():
	if is_instance_valid(game_manager_node):
		if is_instance_valid(ui_human_population_label): # Check if the label exists
			game_manager_node.human_population_changed.connect(_on_human_population_changed)
		if is_instance_valid(ui_turn_wave_label): # Check if the label exists
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
		necromancer_node.spell_upgraded.connect(_on_spell_upgraded)

	if is_instance_valid(ui_level_up_button): ui_level_up_button.pressed.connect(_on_level_up_button_pressed)
	if is_instance_valid(ui_reanimate_button): ui_reanimate_button.pressed.connect(_on_reanimate_button_pressed)
	if is_instance_valid(ui_reanimate_type_button): ui_reanimate_type_button.pressed.connect(_on_reanimate_type_button_pressed)
	if is_instance_valid(ui_soul_drain_button): ui_soul_drain_button.pressed.connect(_on_soul_drain_button_pressed)
	if is_instance_valid(ui_reanimate_upgrade_button): ui_reanimate_upgrade_button.pressed.connect(_on_reanimate_upgrade_button_pressed)
	if is_instance_valid(ui_soul_drain_upgrade_button): ui_soul_drain_upgrade_button.pressed.connect(_on_soul_drain_upgrade_button_pressed)
	if is_instance_valid(ui_proceed_button): ui_proceed_button.pressed.connect(_on_proceed_button_pressed)
	if is_instance_valid(ui_game_over_restart_button): ui_game_over_restart_button.pressed.connect(_on_restart_button_pressed)


# --- UI UPDATE & BUTTON HANDLER FUNCTIONS ---

func _on_human_population_changed(new_population: int):
	if is_instance_valid(ui_human_population_label):
		ui_human_population_label.text = "Humans: %d" % new_population
	# else: print_debug("UI Update: Human Population = %d (Label not found)" % new_population)

func _on_de_changed(current_de: int, max_de: int):
	if is_instance_valid(ui_dark_energy_label): ui_dark_energy_label.text = str(current_de)
	if is_instance_valid(ui_max_dark_energy_label): ui_max_dark_energy_label.text = str(max_de)

func _on_level_changed(new_level: int):
	if is_instance_valid(ui_level_label): ui_level_label.text = "Lvl: %d" % new_level
	if is_instance_valid(ui_mastery_points_label): ui_mastery_points_label.text = "MP: %d" % new_level 

# FIX: Modified to accept arguments, even if not all are used directly in this version.
# The important part is that the signature can accept what the signals send.
func _on_turn_or_wave_changed(_arg1 = null, _arg2 = null): # Accept up to 2 optional args
	if is_instance_valid(ui_turn_wave_label) and is_instance_valid(game_manager_node):
		ui_turn_wave_label.text = "Turn: %d | Wave: %d" % [game_manager_node.current_turn, game_manager_node.current_wave_in_turn]
	# else: print_debug("UI Update: Turn %d, Wave %d (Label not found)" % [game_manager_node.current_turn, game_manager_node.current_wave_in_turn])
	_update_proceed_button_text()

func _on_game_over(_reason_key: String, message: String): # reason_key is passed but not used in label
	if is_instance_valid(ui_game_over_panel) and is_instance_valid(ui_game_over_status_label):
		ui_game_over_status_label.text = "Game Over!\n%s" % message 
		ui_game_over_panel.visible = true
	if is_instance_valid(ui_proceed_button): ui_proceed_button.disabled = true


func _on_player_phase_started(_phase_name: String): # phase_name passed but not directly used here
	_update_proceed_button_text()
	var can_cast_spells = (game_manager_node.current_game_phase == GameManager.GamePhase.PLAYER_PRE_BATTLE or \
						   game_manager_node.current_game_phase == GameManager.GamePhase.PLAYER_POST_BATTLE)
	if is_instance_valid(ui_reanimate_button): ui_reanimate_button.disabled = not can_cast_spells
	if is_instance_valid(ui_soul_drain_button): ui_soul_drain_button.disabled = not can_cast_spells

func _on_battle_phase_started():
	_update_proceed_button_text()
	if is_instance_valid(ui_reanimate_button): ui_reanimate_button.disabled = true
	if is_instance_valid(ui_soul_drain_button): ui_soul_drain_button.disabled = true

func _on_wave_ended(_wave_num, _turn_num): # args passed but not directly used here
	_update_proceed_button_text()

func _on_turn_ended(_turn_num): # arg passed but not directly used here
	_update_proceed_button_text()

func _on_spell_upgraded(spell_data: SpellData):
	if spell_data.spell_name == "Reanimate":
		_update_reanimate_type_button_text() 
		if is_instance_valid(ui_reanimate_upgrade_button):
			ui_reanimate_upgrade_button.disabled = (spell_data.spell_level >= spell_data.max_spell_level)
	elif spell_data.spell_name == "Soul Drain":
		if is_instance_valid(ui_soul_drain_upgrade_button):
			ui_soul_drain_upgrade_button.disabled = (spell_data.spell_level >= spell_data.max_spell_level)


func _on_level_up_button_pressed():
	if is_instance_valid(necromancer_node): 
		necromancer_node.level += 1 
		# print_debug("Necromancer manually leveled up to %d via UI button." % necromancer_node.level)

func _on_reanimate_button_pressed():
	var reanimate_spell = necromancer_node.get_spell_by_name("Reanimate")
	if not is_instance_valid(reanimate_spell): printerr("Game.gd: Reanimate spell not found."); return

	var corpses = game_manager_node.get_available_corpses()
	if corpses.is_empty(): 
		# print_debug("No corpses available to reanimate.")
		return
	var target_corpse = corpses[0] 
	
	# The Reanimate spell's apply_effect uses its *own* spell_level to determine type.
	# current_reanimate_spell_level_selection is a UI hint for the player.
	# We might add a check here if the player's *intended* type (from selection)
	# can actually be produced by the spell's *current* upgraded level.
	# For now, casting will just use the spell's actual current level.
	# Example check:
	# var desired_type_level = current_reanimate_spell_level_selection
	# if reanimate_spell.spell_level < desired_type_level:
	#    print_debug("Cannot reanimate desired type. Spell level %d, need %d." % [reanimate_spell.spell_level, desired_type_level])
	#    return # Or show UI message
	
	necromancer_node.attempt_cast_spell(reanimate_spell, target_corpse)

func _on_reanimate_type_button_pressed():
	current_reanimate_spell_level_selection += 1
	var reanimate_spell = necromancer_node.get_spell_by_name("Reanimate")
	var max_level_for_type_selection = 3 
	if is_instance_valid(reanimate_spell):
		max_level_for_type_selection = reanimate_spell.max_spell_level 
	if current_reanimate_spell_level_selection > max_level_for_type_selection:
		current_reanimate_spell_level_selection = 1
	_update_reanimate_type_button_text()

func _update_reanimate_type_button_text():
	if not is_instance_valid(ui_reanimate_type_button): return
	var type_str = "Skeleton" # Default for level 1 selection
	if current_reanimate_spell_level_selection == 2: type_str = "Zombie"
	elif current_reanimate_spell_level_selection == 3: type_str = "Spirit"
	# This assumes reanimate_spell_resource.max_spell_level is at least 3 for these types.
	# Add more types if spell can go higher.
	ui_reanimate_type_button.text = "Type: %s" % type_str

func _on_soul_drain_button_pressed():
	var soul_drain_spell = necromancer_node.get_spell_by_name("Soul Drain")
	if not is_instance_valid(soul_drain_spell): printerr("Game.gd: Soul Drain spell not found."); return

	var target_creature = null
	if soul_drain_spell._get_num_targets_for_level() == 1: 
		var potential_targets = game_manager_node.get_all_living_humans_and_aliens()
		if not potential_targets.is_empty(): target_creature = potential_targets[0] 
		else: 
			# print_debug("No valid targets for single-target Soul Drain.")
			return
	necromancer_node.attempt_cast_spell(soul_drain_spell, target_creature)

func _on_reanimate_upgrade_button_pressed():
	if is_instance_valid(necromancer_node): necromancer_node.upgrade_spell_by_name("Reanimate")
func _on_soul_drain_upgrade_button_pressed():
	if is_instance_valid(necromancer_node): necromancer_node.upgrade_spell_by_name("Soul Drain")

func _on_proceed_button_pressed():
	if not is_instance_valid(game_manager_node): return
	match game_manager_node.current_game_phase:
		GameManager.GamePhase.OUT_OF_TURN: game_manager_node.proceed_to_next_turn()
		GameManager.GamePhase.PLAYER_PRE_BATTLE: game_manager_node.player_ends_pre_battle_phase()
		GameManager.GamePhase.PLAYER_POST_BATTLE: game_manager_node.player_ends_post_battle_phase()
		GameManager.GamePhase.WAVE_ENDING: game_manager_node.proceed_to_next_wave()
		GameManager.GamePhase.TURN_ENDING: game_manager_node.proceed_to_next_turn()
	_update_proceed_button_text()

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
