# ./scripts/GameManager.gd
extends Node
class_name GameManager

# --- SIGNALS ---
signal turn_started(turn_number: int)
signal wave_started(wave_number: int, turn_number: int)
signal player_phase_started(phase_name: String) 
signal battle_phase_started
signal wave_ended(wave_number: int, turn_number: int)
signal turn_ended(turn_number: int)
signal game_over(reason_key: String, message: String) 
signal human_population_changed(new_population: int)
signal corpse_added(corpse: CorpseData)
signal corpse_removed(corpse: CorpseData) 
signal undead_roster_changed(new_roster: Array[Creature]) 

signal game_event_log_requested(message: String, color_tag: String)


# --- GAME STATE ENUMS ---
enum GamePhase { 
	NONE,                
	OUT_OF_TURN,         
	TURN_STARTING,       
	PLAYER_PRE_BATTLE,   
	BATTLE_IN_PROGRESS,  
	PLAYER_POST_BATTLE,  
	WAVE_ENDING,         
	TURN_ENDING          
}

# --- CORE GAME VARIABLES ---
var current_turn: int = 0
var current_wave_in_turn: int = 0
var max_waves_per_turn: int = 5 
var waves_with_new_aliens: int = 3 
var human_civilian_population: int = 1000 : set = _set_human_civilian_population
const INITIAL_HUMAN_POPULATION: int = 1000
var current_game_phase: GamePhase = GamePhase.NONE

# --- ENTITY MANAGEMENT ---
var living_humans_on_grid: Array[Creature] = []
var living_aliens_on_grid: Array[Creature] = []
var living_undead_on_grid: Array[Creature] = [] 
var player_undead_roster: Array[Creature] = []  
var available_corpses: Array[CorpseData] = []   

# --- NODE REFERENCES ---
var necromancer_node: Necromancer
var battle_grid_node: BattleGrid
var units_container_node: Node2D 

# --- CONFIGURATION ---
const CREATURE_SCRIPT_PATHS = {
	"Skeleton": "res://scripts/creatures/Skeleton.gd", "Zombie": "res://scripts/creatures/Zombie.gd",
	"Spirit": "res://scripts/creatures/Spirit.gd", "Human_Civilian": "res://scripts/creatures/Human.gd", 
	"Human_Swordsman": "res://scripts/creatures/Human.gd", "Human_Archer": "res://scripts/creatures/Human.gd",
	"Human_Knight": "res://scripts/creatures/Human.gd", "Alien_FireAnt": "res://scripts/creatures/Alien.gd",
	"Alien_Wasp": "res://scripts/creatures/Alien.gd", "Alien_Beetle": "res://scripts/creatures/Alien.gd",
}
const INITIAL_FINALITY_FOR_NEW_CORPSES: int = 1 

var combat_log_for_gm_internal: Array[String] = [] 

func _ready():
	# Seed the random number generator
	randomize()


func late_initialize_references(necro: Necromancer, bg: BattleGrid, units_cont: Node2D):
	necromancer_node = necro
	battle_grid_node = bg
	units_container_node = units_cont
	
	if is_instance_valid(battle_grid_node):
		battle_grid_node.assign_runtime_references(self) 
	if is_instance_valid(necromancer_node):
		necromancer_node.assign_runtime_references(self, battle_grid_node)

# --- GAME FLOW CONTROL ---
func start_new_game():
	current_turn = 0
	_set_human_civilian_population(INITIAL_HUMAN_POPULATION) 
	
	for child in units_container_node.get_children():
		if child is Creature: 
			child.queue_free()
	living_humans_on_grid.clear()
	living_aliens_on_grid.clear()
	living_undead_on_grid.clear()
	player_undead_roster.clear()
	available_corpses.clear()
	
	if is_instance_valid(battle_grid_node):
		battle_grid_node.initialize_grid_data() 
	
	if not is_instance_valid(necromancer_node): printerr("GM: NecromancerNode missing at start_new_game!"); get_tree().quit(); return
	if not is_instance_valid(battle_grid_node): printerr("GM: BattleGridNode missing at start_new_game!"); get_tree().quit(); return
	if not is_instance_valid(units_container_node): printerr("GM: UnitsContainerNode missing at start_new_game!"); get_tree().quit(); return
	
	_change_game_phase(GamePhase.OUT_OF_TURN)

func proceed_to_next_turn():
	if current_game_phase != GamePhase.OUT_OF_TURN and current_game_phase != GamePhase.TURN_ENDING and current_game_phase != GamePhase.NONE:
		return
	
	current_turn += 1
	current_wave_in_turn = 0 
	emit_signal("turn_started", current_turn) 
	_change_game_phase(GamePhase.TURN_STARTING)
	
	if is_instance_valid(necromancer_node):
		necromancer_node.replenish_de_to_max() 
		
	_spawn_new_human_contingent() 
	proceed_to_next_wave() 

func proceed_to_next_wave():
	if current_game_phase != GamePhase.TURN_STARTING and \
	   current_game_phase != GamePhase.PLAYER_POST_BATTLE and \
	   current_game_phase != GamePhase.WAVE_ENDING:
		return

	current_wave_in_turn += 1
	if current_wave_in_turn > max_waves_per_turn:
		_end_current_turn() 
		return
		
	emit_signal("wave_started", current_wave_in_turn, current_turn) 
	
	if current_wave_in_turn <= waves_with_new_aliens:
		_spawn_new_alien_wave() 
		
	_change_game_phase(GamePhase.PLAYER_PRE_BATTLE)
	emit_signal("player_phase_started", "PRE_BATTLE") 

func player_ends_pre_battle_phase():
	if current_game_phase != GamePhase.PLAYER_PRE_BATTLE: return
	emit_signal("game_event_log_requested", "Player ends pre-battle preparations.", "white")
	_initiate_battle_phase()

func _initiate_battle_phase():
	_change_game_phase(GamePhase.BATTLE_IN_PROGRESS)
	emit_signal("battle_phase_started") 
	combat_log_for_gm_internal.clear() 
	
	for col_idx in range(battle_grid_node.GRID_COLUMNS):
		_resolve_combat_in_lane(col_idx)
		
	_change_game_phase(GamePhase.PLAYER_POST_BATTLE)
	emit_signal("player_phase_started", "POST_BATTLE_REANIMATE")

func player_ends_post_battle_phase():
	if current_game_phase != GamePhase.PLAYER_POST_BATTLE: return
	emit_signal("game_event_log_requested", "Player ends post-battle actions.", "white")
	_end_current_wave()

# MODIFIED: Logic for handling aliens reaching population and ending wave
func _end_current_wave():
	# IMPORTANT: Process aliens attacking population BEFORE other wave end logic
	_process_aliens_reaching_population()

	emit_signal("wave_ended", current_wave_in_turn, current_turn)
	_change_game_phase(GamePhase.WAVE_ENDING)
	
	# Check for game over due to population loss immediately after processing attacks
	if human_civilian_population <= 0 and current_game_phase != GamePhase.NONE:
		# _set_game_over is already called by _set_human_civilian_population, so no explicit call here needed
		# to avoid double signals if population hits zero.
		return 

	var aliens_remain_on_grid = living_aliens_on_grid.size() > 0
	var more_aliens_expected_this_turn = current_wave_in_turn < waves_with_new_aliens
	
	if not aliens_remain_on_grid and not more_aliens_expected_this_turn:
		emit_signal("game_event_log_requested", "All alien waves cleared for this turn.", "green")
		_end_current_turn()
	# If aliens remain or more are expected, the game proceeds to the next phase (PLAYER_POST_BATTLE -> WAVE_ENDING -> next wave or turn end)

# ADDED: New function to handle aliens attacking the population at the end of a wave
func _process_aliens_reaching_population():
	if not is_instance_valid(battle_grid_node):
		printerr("GM: BattleGridNode not valid in _process_aliens_reaching_population.")
		return

	var player_home_row_y = battle_grid_node.get_player_row_y_by_faction_row_num(1) # Player's "back line"
	if player_home_row_y == -1:
		printerr("GM: Could not determine player home row Y for population attack.")
		return

	# Iterate over a copy because we might remove aliens from the original list
	for alien_unit in living_aliens_on_grid.duplicate(): 
		if not is_instance_valid(alien_unit) or not alien_unit.is_alive:
			continue

		if alien_unit.grid_pos.y == player_home_row_y:
			# Alien has reached the population
			var damage_to_population = alien_unit.level * alien_unit.attack_power * randi_range(1, 10)
			
			emit_signal("game_event_log_requested", 
				"Alien '%s' (Lvl %d, AP %d) broke through, dealing %d damage to population!" % \
				[alien_unit.creature_name, alien_unit.level, alien_unit.attack_power, damage_to_population], 
				"red")
			
			_set_human_civilian_population(human_civilian_population - damage_to_population)
			
			# Remove the alien from the game after it attacks
			_remove_creature_from_game(alien_unit, "attacked population and was removed")
			
			# If population drops to 0, game over state will be handled by _set_human_civilian_population
			if human_civilian_population <= 0:
				break # Stop processing more aliens if population is already zero


# MODIFIED: Removed direct population damage from end of turn, now handled per wave
func _end_current_turn():
	_change_game_phase(GamePhase.TURN_ENDING)
	
	# REMOVED: Logic for passed_aliens_this_turn and _handle_alien_pass_through.
	# This is now handled by _process_aliens_reaching_population() at the end of each wave.

	# Corpse decay at end of turn
	for corpse_to_remove in available_corpses.duplicate(): 
		_remove_corpse_from_list(corpse_to_remove, "decayed at turn end") 
	# available_corpses.clear() # _remove_corpse_from_list already modifies the list
	
	emit_signal("turn_ended", current_turn) 
	
	if current_turn >= 20 and human_civilian_population > 0: 
		_set_game_over("player_won", "Survived all turns!") 
		return
	if human_civilian_population <= 0 and current_game_phase != GamePhase.NONE: 
		# Game over due to population loss is handled by _set_human_civilian_population
		return
		
	_change_game_phase(GamePhase.OUT_OF_TURN) 

func _set_human_civilian_population(value: int):
	var old_pop = human_civilian_population
	human_civilian_population = max(0, value) 
	if old_pop != human_civilian_population:
		emit_signal("human_population_changed", human_civilian_population) 
		if human_civilian_population == 0 and current_game_phase != GamePhase.NONE: 
			_set_game_over("humans_extinct", "Human population reached zero.")

func _change_game_phase(new_phase: GamePhase):
	if current_game_phase != new_phase:
		# print_debug("GamePhase changed from %s to %s" % [GamePhase.keys()[current_game_phase], GamePhase.keys()[new_phase]])
		current_game_phase = new_phase

func _set_game_over(reason_key: String, message: String): 
	if current_game_phase == GamePhase.NONE and reason_key != "": return 
	# print_debug("GAME OVER: %s - %s" % [reason_key, message])
	_change_game_phase(GamePhase.NONE) 
	emit_signal("game_over", reason_key, message)


# --- UNIT SPAWNING AND MANAGEMENT ---
func _spawn_new_human_contingent():
	emit_signal("game_event_log_requested", "Human reinforcements arriving for Turn %d." % current_turn, "green")
	# TODO: Implement configuration-driven human spawning and level assignment
	var humans_to_spawn: Array[Dictionary] = [
		{"type": "Human_Swordsman", "config": {"creature_name": "Swordsman", "level": 1, "max_health": 15, "attack_power": 4, "speed_type": Creature.SpeedType.NORMAL, "sprite_texture_path": "res://assets/images/placerholder_swordsman.png"}},
		{"type": "Human_Archer", "config": {"creature_name": "Archer", "level": 1, "max_health": 10, "attack_power": 3, "speed_type": Creature.SpeedType.NORMAL, "has_reach": true, "sprite_texture_path": "res://assets/images/placerholder_archer.png"}},
		{"type": "Human_Civilian", "config": {"creature_name": "Civilian", "level": 1, "max_health": 5, "attack_power": 0, "speed_type": Creature.SpeedType.SLOW, "sprite_texture_path": "res://assets/images/placerholder_civilian.png"}},
	]
	_auto_place_units(humans_to_spawn, Creature.Faction.HUMAN, "Human")

# MODIFIED: Assign temporary level to aliens based on wave number
func _spawn_new_alien_wave():
	emit_signal("game_event_log_requested", "New alien wave %d (Turn %d) inbound!" % [current_wave_in_turn, current_turn], "red")
	# TODO: Implement configuration-driven alien spawning
	var aliens_to_spawn: Array[Dictionary] = [
		{"type": "Alien_FireAnt", "config": {"creature_name": "FireAnt", "level": current_wave_in_turn, "max_health": 8 + current_wave_in_turn, "attack_power": 3 + (current_wave_in_turn / 2), "speed_type": Creature.SpeedType.FAST, "sprite_texture_path": "res://assets/images/placeholder_fireant.png"}},
		{"type": "Alien_Wasp", "config": {"creature_name": "Wasp", "level": current_wave_in_turn, "max_health": 6 + current_wave_in_turn, "attack_power": 2 + (current_wave_in_turn / 2), "speed_type": Creature.SpeedType.FAST, "is_flying": true, "sprite_texture_path": "res://assets/images/placeholder_wasp.png"}},
	]
	if current_wave_in_turn >= 2: # Introduce Beetle from wave 2 onwards
		aliens_to_spawn.append({"type": "Alien_Beetle", "config": {"creature_name": "Beetle", "level": current_wave_in_turn, "max_health": 20 + (current_wave_in_turn * 2), "attack_power": 2 + current_wave_in_turn, "speed_type": Creature.SpeedType.SLOW, "sprite_texture_path": "res://assets/images/placeholder_beetle.png"}})
	
	_auto_place_units(aliens_to_spawn, Creature.Faction.ALIEN, "Alien")

func _auto_place_units(units_to_spawn_data: Array[Dictionary], faction: Creature.Faction, faction_name_for_log: String):
	if not is_instance_valid(battle_grid_node):
		printerr("GM: BattleGridNode not valid in _auto_place_units.")
		return
		
	var faction_rows_y_coords: Array[int] = [] 

	if faction == Creature.Faction.HUMAN or faction == Creature.Faction.UNDEAD: 
		faction_rows_y_coords = [
			battle_grid_node.get_player_row_y_by_faction_row_num(1), 
			battle_grid_node.get_player_row_y_by_faction_row_num(2), 
			battle_grid_node.get_player_row_y_by_faction_row_num(3)  
		]
	elif faction == Creature.Faction.ALIEN:
		faction_rows_y_coords = [
			battle_grid_node.get_alien_row_y_by_faction_row_num(1), 
			battle_grid_node.get_alien_row_y_by_faction_row_num(2), 
			battle_grid_node.get_alien_row_y_by_faction_row_num(3)  
		]
	else:
		printerr("GM: _auto_place_units called with invalid faction: %s" % Creature.Faction.keys()[faction])
		return

	for unit_data in units_to_spawn_data:
		var creature_node: Creature = _create_creature_node_from_config(unit_data["type"], unit_data["config"], faction)
		if not is_instance_valid(creature_node):
			printerr("GM: Failed to create creature node for auto-placement: %s" % unit_data["type"])
			continue

		var placed = false
		# Try placing from front-most row for faction to back-most
		var rows_to_try = faction_rows_y_coords.duplicate() # Use a copy
		if faction == Creature.Faction.HUMAN or faction == Creature.Faction.UNDEAD:
			rows_to_try.reverse() # Player front is row 3 (index 2), back is row 1 (index 0)

		for row_y in rows_to_try: 
			if row_y == -1: continue 

			var target_pos = battle_grid_node.find_first_empty_cell_in_row(row_y)
			if target_pos != Vector2i(-1,-1): 
				if battle_grid_node.place_creature_at(creature_node, target_pos):
					_add_creature_to_active_lists(creature_node)
					emit_signal("game_event_log_requested", "%s '%s' (Lvl %d) deployed at %s." % [faction_name_for_log, creature_node.creature_name, creature_node.level, str(target_pos)], "green")
					placed = true
					break 
		
		if not placed:
			emit_signal("game_event_log_requested", "Could not place %s '%s' (Lvl %d)." % [faction_name_for_log, unit_data["config"].get("creature_name", unit_data["type"]), unit_data["config"].get("level",1)], "yellow")
			creature_node.queue_free() 

func _prepare_creature_node_base() -> Node2D:
	var creature_base_node = Node2D.new()
	var sprite_node = Sprite2D.new()
	sprite_node.name = "Sprite" 
	creature_base_node.add_child(sprite_node)
	return creature_base_node

func spawn_reanimated_creature(config_from_spell: Dictionary, grid_pos_to_spawn: Vector2i) -> Creature: 
	var script_path = config_from_spell.get("creature_class_script_path", "")
	if script_path == "": printerr("GM: No script_path provided for reanimation."); return null
	
	var creature_node_base = _prepare_creature_node_base()
	var script_resource = load(script_path)
	if not script_resource:
		printerr("GM: Failed to load script resource at %s" % script_path)
		creature_node_base.queue_free(); return null
	
	creature_node_base.set_script(script_resource)
	var actual_creature: Creature = creature_node_base as Creature 
	
	if not is_instance_valid(actual_creature):
		printerr("GM: Node did not correctly become a Creature after script set: %s" % script_path)
		creature_node_base.queue_free(); return null
		
	actual_creature.game_manager = self
	actual_creature.battle_grid = battle_grid_node
	
	var final_config = config_from_spell.duplicate(true) 
	final_config["faction"] = Creature.Faction.UNDEAD
	final_config["level"] = config_from_spell.get("level", 1) # Ensure level is passed for reanimated
	
	var undead_type_name = config_from_spell.get("creature_name", "Undead").to_lower()
	if not final_config.has("sprite_texture_path"):
		if undead_type_name.contains("skeleton"): final_config["sprite_texture_path"] = "res://assets/images/placeholder_skeleton.png"
		elif undead_type_name.contains("zombie"): final_config["sprite_texture_path"] = "res://assets/images/placeholder_zombie.png"
		elif undead_type_name.contains("spirit"): final_config["sprite_texture_path"] = "res://assets/images/placeholder_spirit.png"
		else: final_config["sprite_texture_path"] = "res://assets/images/placeholder_undead.png" 
		
	actual_creature.initialize_creature(final_config) 
	units_container_node.add_child(actual_creature) 
	
	if battle_grid_node.place_creature_at(actual_creature, grid_pos_to_spawn):
		_add_creature_to_active_lists(actual_creature) 
		emit_signal("game_event_log_requested", "Reanimated '%s' (Lvl %d, Finality: %d) rises at %s!" % [actual_creature.creature_name, actual_creature.level, actual_creature.finality_counter, str(grid_pos_to_spawn)], "green")
	else:
		emit_signal("game_event_log_requested", "Failed to place reanimated '%s' (Lvl %d) at %s. Adding to roster." % [actual_creature.creature_name, actual_creature.level, str(grid_pos_to_spawn)], "yellow")
		if not player_undead_roster.has(actual_creature):
			player_undead_roster.append(actual_creature)
		if living_undead_on_grid.has(actual_creature):
			living_undead_on_grid.erase(actual_creature)

	emit_signal("undead_roster_changed", player_undead_roster) 
	
	if not actual_creature.died.is_connected(_on_creature_died):
		actual_creature.died.connect(_on_creature_died)
		
	return actual_creature

func _create_creature_node_from_config(type_key: String, config: Dictionary, faction_override: Creature.Faction) -> Creature:
	var script_path = CREATURE_SCRIPT_PATHS.get(type_key, "")
	if script_path == "":
		printerr("GM: No script path defined for creature type_key: %s" % type_key)
		return null
	
	var creature_node_base = _prepare_creature_node_base()
	var script_resource = load(script_path)
	if not script_resource:
		printerr("GM: Failed to load script resource for %s at %s" % [type_key, script_path])
		creature_node_base.queue_free(); return null
		
	creature_node_base.set_script(script_resource)
	var actual_creature: Creature = creature_node_base as Creature
	
	if not is_instance_valid(actual_creature):
		printerr("GM: Node did not correctly become a Creature for type_key: %s" % type_key)
		creature_node_base.queue_free(); return null
		
	actual_creature.game_manager = self
	actual_creature.battle_grid = battle_grid_node
	
	var final_cfg = config.duplicate(true)
	final_cfg["faction"] = faction_override 
	# Ensure level is part of the config, defaulting to 1 if not specified
	if not final_cfg.has("level"):
		final_cfg["level"] = 1 
	
	if not final_cfg.has("sprite_texture_path") or final_cfg["sprite_texture_path"] == "res://icon.svg":
		var placeholder_name = type_key.to_lower().replace("human_", "").replace("alien_", "")
		final_cfg["sprite_texture_path"] = "res://assets/images/placeholder_%s.png" % placeholder_name
		
	actual_creature.initialize_creature(final_cfg)
	units_container_node.add_child(actual_creature)
	
	if not actual_creature.died.is_connected(_on_creature_died):
		actual_creature.died.connect(_on_creature_died)
		
	return actual_creature

func _add_creature_to_active_lists(creature: Creature):
	if not is_instance_valid(creature): return
	match creature.faction:
		Creature.Faction.HUMAN:
			if not living_humans_on_grid.has(creature): living_humans_on_grid.append(creature)
		Creature.Faction.ALIEN:
			if not living_aliens_on_grid.has(creature): living_aliens_on_grid.append(creature)
		Creature.Faction.UNDEAD:
			if not living_undead_on_grid.has(creature): living_undead_on_grid.append(creature)
			if player_undead_roster.has(creature): # If deployed from roster
				player_undead_roster.erase(creature)
				emit_signal("undead_roster_changed", player_undead_roster)

func _on_creature_died(creature_died: Creature):
	if not is_instance_valid(creature_died): return
	
	var faction_str = Creature.Faction.keys()[creature_died.faction]
	emit_signal("game_event_log_requested", "%s '%s' (Lvl %d, HP: 0/%d) has fallen!" % [faction_str, creature_died.creature_name, creature_died.level, creature_died.max_health], "red")

	var corpse_payload = creature_died.get_data_for_corpse_creation() 
	corpse_payload["grid_pos_on_death"] = creature_died.grid_pos 
	corpse_payload["turn_of_death"] = current_turn
	
	if creature_died.faction == Creature.Faction.HUMAN or creature_died.faction == Creature.Faction.ALIEN:
		corpse_payload["finality_counter"] = INITIAL_FINALITY_FOR_NEW_CORPSES
	else: # Undead
		corpse_payload["finality_counter"] = corpse_payload.get("current_finality_counter_on_death", 0)
		
	var new_corpse = CorpseData.new(corpse_payload)
	available_corpses.append(new_corpse)
	emit_signal("corpse_added", new_corpse)
	emit_signal("game_event_log_requested", "Corpse of %s (Lvl %d) appears (Finality: %d)." % [new_corpse.original_creature_name, new_corpse.original_level, new_corpse.finality_counter], "yellow")
	
	_remove_creature_from_game(creature_died, "died")

func _remove_creature_from_game(creature_to_remove: Creature, reason: String = "removed"):
	if not is_instance_valid(creature_to_remove): return
	
	var creature_name_for_log = creature_to_remove.creature_name
	var creature_level_for_log = creature_to_remove.level
	var faction_str = Creature.Faction.keys()[creature_to_remove.faction]
	
	if reason != "died": # Avoid double logging death, death is logged by _on_creature_died
		emit_signal("game_event_log_requested", "%s '%s' (Lvl %d) %s from grid." % [faction_str, creature_name_for_log, creature_level_for_log, reason], "yellow") # Changed color to yellow for non-death removals

	if battle_grid_node.is_valid_grid_position(creature_to_remove.grid_pos):
		battle_grid_node.remove_creature_from(creature_to_remove.grid_pos) # This also emits cell_vacated
		
	match creature_to_remove.faction:
		Creature.Faction.HUMAN: living_humans_on_grid.erase(creature_to_remove)
		Creature.Faction.ALIEN: living_aliens_on_grid.erase(creature_to_remove)
		Creature.Faction.UNDEAD:
			living_undead_on_grid.erase(creature_to_remove)
			if player_undead_roster.has(creature_to_remove): # Should not happen if it was on grid, but as a safeguard
				player_undead_roster.erase(creature_to_remove)
				emit_signal("undead_roster_changed", player_undead_roster)
				
	if not creature_to_remove.is_queued_for_deletion():
		creature_to_remove.queue_free()

func consume_corpse(corpse: CorpseData): 
	if available_corpses.has(corpse):
		emit_signal("game_event_log_requested", "Corpse of %s (Lvl %d) consumed for reanimation." % [corpse.original_creature_name, corpse.original_level], "white") # Changed color
		available_corpses.erase(corpse)
		emit_signal("corpse_removed", corpse)

func _remove_corpse_from_list(corpse: CorpseData, reason: String = "removed"): 
	if available_corpses.has(corpse):
		emit_signal("game_event_log_requested", "Corpse of %s (Lvl %d) %s." % [corpse.original_creature_name, corpse.original_level, reason], "white") # Changed color
		available_corpses.erase(corpse)
		emit_signal("corpse_removed", corpse)

# --- COMBAT RESOLUTION ---
# MODIFIED: Handle flying aliens bypassing combat and logging levels
func _resolve_combat_in_lane(col_idx: int) -> bool:
	var combat_occurred_this_lane = false
	while true: # Loop to handle multiple combats if units die and new ones engage
		var player_unit: Creature = null
		var alien_unit: Creature = null

		# Find player unit in the column (front-most first)
		var player_rows_to_search = [
			battle_grid_node.get_player_row_y_by_faction_row_num(3), # Front line for player
			battle_grid_node.get_player_row_y_by_faction_row_num(2),
			battle_grid_node.get_player_row_y_by_faction_row_num(1)  # Back line for player
		]
		for r_y in player_rows_to_search:
			if r_y == -1: continue 
			var c = battle_grid_node.get_creature_at(Vector2i(col_idx, r_y))
			if is_instance_valid(c) and c.is_alive and (c.faction == Creature.Faction.HUMAN or c.faction == Creature.Faction.UNDEAD):
				player_unit = c; break 

		# Find alien unit in the column (front-most first)
		var alien_rows_to_search = [
			battle_grid_node.get_alien_row_y_by_faction_row_num(3), # Front line for alien
			battle_grid_node.get_alien_row_y_by_faction_row_num(2),
			battle_grid_node.get_alien_row_y_by_faction_row_num(1)  # Back line for alien
		]
		for r_y in alien_rows_to_search:
			if r_y == -1: continue
			var c = battle_grid_node.get_creature_at(Vector2i(col_idx, r_y))
			if is_instance_valid(c) and c.is_alive and c.faction == Creature.Faction.ALIEN:
				alien_unit = c; break 

		# If no pair to fight, break the loop for this lane
		if not is_instance_valid(player_unit) or not is_instance_valid(alien_unit):
			break 

		combat_occurred_this_lane = true
		var p_name = player_unit.creature_name
		var p_lvl = player_unit.level
		var a_name = alien_unit.creature_name
		var a_lvl = alien_unit.level
		var p_fac_str = Creature.Faction.keys()[player_unit.faction]
		var a_fac_str = Creature.Faction.keys()[alien_unit.faction]

		# Check if alien flies over player unit
		if alien_unit.is_flying and not player_unit.is_flying and not player_unit.has_reach:
			emit_signal("game_event_log_requested", "%s '%s' (Lvl %d) flies over %s '%s' (Lvl %d)!" % [a_fac_str, a_name, a_lvl, p_fac_str, p_name, p_lvl], "yellow")
			# Alien is removed. If it lands in the last row, _process_aliens_reaching_population will handle it.
			# For now, it's just removed from its current combat spot.
			_remove_creature_from_game(alien_unit, "flew over and bypassed combat")
			# Alien removed, re-evaluate this lane for new combat pair (e.g. player vs next alien if any)
			continue 
		
		# Standard combat damage exchange
		var p_hp_old = player_unit.current_health
		var a_hp_old = alien_unit.current_health
		var p_ap = player_unit.attack_power
		var a_ap = alien_unit.attack_power

		# Player attacks Alien
		emit_signal("game_event_log_requested", "%s '%s' (L%d AP:%d) attacks %s '%s' (L%d HP:%d)." % [p_fac_str, p_name, p_lvl, p_ap, a_fac_str, a_name, a_lvl, a_hp_old], "white")
		alien_unit.take_damage(p_ap) 
		emit_signal("game_event_log_requested", " -> '%s' takes %d damage. HP: %d/%d." % [a_name, p_ap, alien_unit.current_health, alien_unit.max_health], "white")
		
		# Alien attacks Player (if still alive after player's attack)
		if alien_unit.is_alive:
			emit_signal("game_event_log_requested", "%s '%s' (L%d AP:%d) attacks %s '%s' (L%d HP:%d)." % [a_fac_str, a_name, a_lvl, a_ap, p_fac_str, p_name, p_lvl, p_hp_old], "white")
			player_unit.take_damage(a_ap)
			emit_signal("game_event_log_requested", " -> '%s' takes %d damage. HP: %d/%d." % [p_name, a_ap, player_unit.current_health, player_unit.max_health], "white")

		# If either died, the loop continues to see if another combat can occur in the same lane.
		# If both survived, combat in this lane for this "sub-turn" is over.
		if (is_instance_valid(player_unit) and not player_unit.is_alive) or \
		   (is_instance_valid(alien_unit) and not alien_unit.is_alive):
			pass # Deaths are handled by signals, loop will re-evaluate lane
		else:
			break # Both survived, end combat for this lane in this pass.
			
	return combat_occurred_this_lane

# REMOVED: _handle_alien_pass_through function. Its logic is now split:
# - Flying over is handled directly in _resolve_combat_in_lane.
# - Population damage from aliens reaching the end is handled by _process_aliens_reaching_population.

# --- UTILITY / GETTER METHODS ---
func get_available_corpses() -> Array[CorpseData]:
	return available_corpses.filter(func(c): return is_instance_valid(c) and c is CorpseData)

func get_all_living_humans_and_aliens() -> Array[Creature]:
	var all_living_non_undead: Array[Creature] = []
	all_living_non_undead.append_array(living_humans_on_grid.filter(func(c): return is_instance_valid(c) and c.is_alive))
	all_living_non_undead.append_array(living_aliens_on_grid.filter(func(c): return is_instance_valid(c) and c.is_alive))
	return all_living_non_undead

func get_player_undead_roster() -> Array[Creature]:
	return player_undead_roster.filter(func(c): return is_instance_valid(c)) 

# --- PLAYER ACTIONS ---
func player_deploys_undead_from_roster(undead: Creature, grid_pos: Vector2i) -> bool:
	if current_game_phase != GamePhase.PLAYER_PRE_BATTLE and current_game_phase != GamePhase.PLAYER_POST_BATTLE :
		emit_signal("game_event_log_requested", "Cannot deploy Undead. Not in valid phase.", "yellow")
		return false
	if not is_instance_valid(undead) or not player_undead_roster.has(undead):
		emit_signal("game_event_log_requested", "Cannot deploy Undead. Invalid or not in roster.", "yellow")
		return false

	var p_row1_y = battle_grid_node.get_player_row_y_by_faction_row_num(1) 
	var p_row2_y = battle_grid_node.get_player_row_y_by_faction_row_num(2) 
	var p_row3_y = battle_grid_node.get_player_row_y_by_faction_row_num(3) 

	var allowed_rows_y_coords: Array[int] = []
	match undead.speed_type: # Deployment depth based on speed
		Creature.SpeedType.SLOW: allowed_rows_y_coords = [p_row1_y] # Back line only
		Creature.SpeedType.NORMAL: allowed_rows_y_coords = [p_row1_y, p_row2_y] # Back or mid
		Creature.SpeedType.FAST: allowed_rows_y_coords = [p_row1_y, p_row2_y, p_row3_y] # Any player row
	
	allowed_rows_y_coords = allowed_rows_y_coords.filter(func(y): return y != -1) # Remove invalid rows

	if not allowed_rows_y_coords.has(grid_pos.y) or not battle_grid_node.get_player_rows_indices().has(grid_pos.y) :
		emit_signal("game_event_log_requested", "Deploy Undead %s (Lvl %d) to %s failed. Not an allowed player row for its speed." % [undead.creature_name, undead.level, str(grid_pos)], "yellow")
		return false

	if battle_grid_node.place_creature_at(undead, grid_pos):
		_add_creature_to_active_lists(undead) 
		emit_signal("game_event_log_requested", "Undead '%s' (Lvl %d) deployed from roster to %s." % [undead.creature_name, undead.level, str(grid_pos)], "green")
		return true
	else:
		emit_signal("game_event_log_requested", "Failed to place Undead %s (Lvl %d) at %s (cell occupied/invalid)." % [undead.creature_name, undead.level, str(grid_pos)], "yellow")
		return false

func player_returns_undead_to_roster(undead: Creature) -> bool:
	if current_game_phase != GamePhase.PLAYER_PRE_BATTLE and current_game_phase != GamePhase.PLAYER_POST_BATTLE:
		emit_signal("game_event_log_requested", "Cannot return Undead to roster. Not in valid phase.", "yellow")
		return false
	if not is_instance_valid(undead) or not living_undead_on_grid.has(undead):
		emit_signal("game_event_log_requested", "Cannot return Undead. Invalid instance or not on grid.", "yellow")
		return false

	var old_pos = undead.grid_pos
	var removed_creature_ref = battle_grid_node.remove_creature_from(old_pos) 

	if removed_creature_ref == undead: 
		living_undead_on_grid.erase(undead) # Remove from active grid list
		if not player_undead_roster.has(undead): # Add to roster if not already there
			player_undead_roster.append(undead)
		emit_signal("undead_roster_changed", player_undead_roster)
		undead.grid_pos = Vector2i(-1,-1) # Invalidate grid position
		emit_signal("game_event_log_requested", "Undead '%s' (Lvl %d) returned from %s to roster." % [undead.creature_name, undead.level, str(old_pos)], "white")
		return true
	else:
		# This case should ideally not happen if creature was in living_undead_on_grid
		emit_signal("game_event_log_requested", "Failed to remove Undead %s (Lvl %d) from grid at %s during roster return." % [undead.creature_name, undead.level, str(old_pos)], "yellow")
		# Attempt to reconcile lists
		if living_undead_on_grid.has(undead): living_undead_on_grid.erase(undead) 
		if not player_undead_roster.has(undead): player_undead_roster.append(undead) 
		emit_signal("undead_roster_changed", player_undead_roster) 
		return false
