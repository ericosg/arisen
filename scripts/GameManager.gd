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
signal game_over(reason_key: String, message: String) # Added message to GameOver
signal human_population_changed(new_population: int)
signal corpse_added(corpse: CorpseData)
signal corpse_removed(corpse: CorpseData) # For when a corpse is used or decays
signal undead_roster_changed(new_roster: Array[Creature]) 

# New signal for detailed, color-coded game event logging
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

var combat_log_for_gm_internal: Array[String] = [] # Internal combat log if needed, distinct from UI log

func _ready():
	pass

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
	emit_signal("turn_started", current_turn) # Game.gd logs this
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
		
	emit_signal("wave_started", current_wave_in_turn, current_turn) # Game.gd logs this
	
	if current_wave_in_turn <= waves_with_new_aliens:
		_spawn_new_alien_wave() 
		
	_change_game_phase(GamePhase.PLAYER_PRE_BATTLE)
	emit_signal("player_phase_started", "PRE_BATTLE") # Game.gd logs this

func player_ends_pre_battle_phase():
	if current_game_phase != GamePhase.PLAYER_PRE_BATTLE: return
	emit_signal("game_event_log_requested", "Player ends pre-battle preparations.", "white")
	_initiate_battle_phase()

func _initiate_battle_phase():
	_change_game_phase(GamePhase.BATTLE_IN_PROGRESS)
	emit_signal("battle_phase_started") # Game.gd logs this
	combat_log_for_gm_internal.clear() 
	
	for col_idx in range(battle_grid_node.GRID_COLUMNS):
		_resolve_combat_in_lane(col_idx)
		
	_change_game_phase(GamePhase.PLAYER_POST_BATTLE)
	emit_signal("player_phase_started", "POST_BATTLE_REANIMATE") # Game.gd logs this

func player_ends_post_battle_phase():
	if current_game_phase != GamePhase.PLAYER_POST_BATTLE: return
	emit_signal("game_event_log_requested", "Player ends post-battle actions.", "white")
	_end_current_wave()

func _end_current_wave():
	emit_signal("wave_ended", current_wave_in_turn, current_turn) # Game.gd logs this
	_change_game_phase(GamePhase.WAVE_ENDING)
	
	var aliens_remain_on_grid = living_aliens_on_grid.size() > 0
	var more_aliens_expected_this_turn = current_wave_in_turn < waves_with_new_aliens
	
	if not aliens_remain_on_grid and not more_aliens_expected_this_turn:
		emit_signal("game_event_log_requested", "All alien waves cleared for this turn.", "green")
		_end_current_turn()

func _end_current_turn():
	_change_game_phase(GamePhase.TURN_ENDING)
	
	var passed_aliens_this_turn: Array[Creature] = []
	for alien_unit in living_aliens_on_grid.duplicate(): 
		if not is_instance_valid(alien_unit) or not alien_unit.is_alive:
			continue
		var player_home_row_y = battle_grid_node.get_player_row_y_by_faction_row_num(1) 
		if alien_unit.grid_pos.y == player_home_row_y:
			passed_aliens_this_turn.append(alien_unit)
			
	for alien_passed in passed_aliens_this_turn:
		_handle_alien_pass_through(alien_passed, "EndTurnPass") # Emits log
		if is_instance_valid(alien_passed): 
			_remove_creature_from_game(alien_passed, "passed through") # Emits log

	for corpse_to_remove in available_corpses.duplicate(): 
		_remove_corpse_from_list(corpse_to_remove, "decayed") # Emits log
	available_corpses.clear() 
	
	emit_signal("turn_ended", current_turn) # Game.gd logs this
	
	if current_turn >= 20 and human_civilian_population > 0: 
		_set_game_over("player_won", "Survived all turns!") # Emits log via _set_game_over
		return
	if human_civilian_population <= 0: 
		return
		
	_change_game_phase(GamePhase.OUT_OF_TURN) 

func _set_human_civilian_population(value: int):
	var old_pop = human_civilian_population
	human_civilian_population = max(0, value) 
	if old_pop != human_civilian_population:
		emit_signal("human_population_changed", human_civilian_population) # Game.gd logs this
		if human_civilian_population == 0 and current_game_phase != GamePhase.NONE: 
			_set_game_over("humans_extinct", "Human population reached zero.")

func _change_game_phase(new_phase: GamePhase):
	if current_game_phase != new_phase:
		current_game_phase = new_phase

func _set_game_over(reason_key: String, message: String): 
	if current_game_phase == GamePhase.NONE and reason_key != "": return 
	_change_game_phase(GamePhase.NONE) 
	emit_signal("game_over", reason_key, message) # Game.gd logs this using message


# --- UNIT SPAWNING AND MANAGEMENT ---
func _spawn_new_human_contingent():
	emit_signal("game_event_log_requested", "Human reinforcements arriving for Turn %d." % current_turn, "green")
	var humans_to_spawn: Array[Dictionary] = [
		{"type": "Human_Swordsman", "config": {"creature_name": "Swordsman", "max_health": 15, "attack_power": 4, "speed_type": Creature.SpeedType.NORMAL, "sprite_texture_path": "res://assets/images/placerholder_swordsman.png"}},
		{"type": "Human_Archer", "config": {"creature_name": "Archer", "max_health": 10, "attack_power": 3, "speed_type": Creature.SpeedType.NORMAL, "has_reach": true, "sprite_texture_path": "res://assets/images/placerholder_archer.png"}},
		{"type": "Human_Civilian", "config": {"creature_name": "Civilian", "max_health": 5, "attack_power": 0, "speed_type": Creature.SpeedType.SLOW, "sprite_texture_path": "res://assets/images/placerholder_civilian.png"}},
	]
	_auto_place_units(humans_to_spawn, Creature.Faction.HUMAN, "Human")

func _spawn_new_alien_wave():
	emit_signal("game_event_log_requested", "New alien wave %d inbound!" % current_wave_in_turn, "red")
	var aliens_to_spawn: Array[Dictionary] = [
		{"type": "Alien_FireAnt", "config": {"creature_name": "FireAnt", "max_health": 8, "attack_power": 3, "speed_type": Creature.SpeedType.FAST, "sprite_texture_path": "res://assets/images/placeholder_fireant.png"}},
		{"type": "Alien_Wasp", "config": {"creature_name": "Wasp", "max_health": 6, "attack_power": 2, "speed_type": Creature.SpeedType.FAST, "is_flying": true, "sprite_texture_path": "res://assets/images/placeholder_wasp.png"}},
	]
	if current_wave_in_turn == 2: 
		aliens_to_spawn.append({"type": "Alien_Beetle", "config": {"creature_name": "Beetle", "max_health": 20, "attack_power": 2, "speed_type": Creature.SpeedType.SLOW, "sprite_texture_path": "res://assets/images/placeholder_beetle.png"}})
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
		for row_y in faction_rows_y_coords: 
			if row_y == -1: continue 

			var target_pos = battle_grid_node.find_first_empty_cell_in_row(row_y)
			if target_pos != Vector2i(-1,-1): 
				if battle_grid_node.place_creature_at(creature_node, target_pos):
					_add_creature_to_active_lists(creature_node)
					emit_signal("game_event_log_requested", "%s '%s' deployed at %s." % [faction_name_for_log, creature_node.creature_name, str(target_pos)], "green")
					placed = true
					break 
		
		if not placed:
			emit_signal("game_event_log_requested", "Could not place %s '%s'." % [faction_name_for_log, unit_data["config"].get("creature_name", unit_data["type"])], "yellow")
			creature_node.queue_free() 

func _prepare_creature_node_base() -> Node2D:
	var creature_base_node = Node2D.new()
	var sprite_node = Sprite2D.new()
	sprite_node.name = "Sprite" 
	creature_base_node.add_child(sprite_node)
	return creature_base_node

func spawn_reanimated_creature(config_from_spell: Dictionary, grid_pos_to_spawn: Vector2i) -> Creature: # Added grid_pos
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
	
	var undead_type_name = config_from_spell.get("creature_name", "Undead").to_lower()
	if not final_config.has("sprite_texture_path"):
		if undead_type_name.contains("skeleton"): final_config["sprite_texture_path"] = "res://assets/images/placeholder_skeleton.png"
		elif undead_type_name.contains("zombie"): final_config["sprite_texture_path"] = "res://assets/images/placeholder_zombie.png"
		elif undead_type_name.contains("spirit"): final_config["sprite_texture_path"] = "res://assets/images/placeholder_spirit.png"
		else: final_config["sprite_texture_path"] = "res://assets/images/placeholder_undead.png" 
		
	actual_creature.initialize_creature(final_config) 
	units_container_node.add_child(actual_creature) 
	
	# Attempt to place the reanimated creature on the grid
	if battle_grid_node.place_creature_at(actual_creature, grid_pos_to_spawn):
		_add_creature_to_active_lists(actual_creature) # This adds to living_undead_on_grid
		emit_signal("game_event_log_requested", "Reanimated '%s' (Finality: %d) rises at %s!" % [actual_creature.creature_name, actual_creature.finality_counter, str(grid_pos_to_spawn)], "green")
	else:
		# If placement fails (e.g., cell occupied by something else unexpectedly)
		emit_signal("game_event_log_requested", "Failed to place reanimated '%s' at %s. Adding to roster." % [actual_creature.creature_name, str(grid_pos_to_spawn)], "yellow")
		# Add to roster instead of grid if placement fails
		if not player_undead_roster.has(actual_creature):
			player_undead_roster.append(actual_creature)
		# Ensure it's not in living_undead_on_grid if not placed
		if living_undead_on_grid.has(actual_creature):
			living_undead_on_grid.erase(actual_creature)

	emit_signal("undead_roster_changed", player_undead_roster) # Roster might change if placed or not
	
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
			if player_undead_roster.has(creature):
				player_undead_roster.erase(creature)
				emit_signal("undead_roster_changed", player_undead_roster)

func _on_creature_died(creature_died: Creature):
	if not is_instance_valid(creature_died): return
	
	var faction_str = Creature.Faction.keys()[creature_died.faction]
	emit_signal("game_event_log_requested", "%s '%s' (HP: 0/%d) has fallen!" % [faction_str, creature_died.creature_name, creature_died.max_health], "red")

	var corpse_payload = creature_died.get_data_for_corpse_creation() 
	corpse_payload["grid_pos_on_death"] = creature_died.grid_pos 
	corpse_payload["turn_of_death"] = current_turn
	
	if creature_died.faction == Creature.Faction.HUMAN or creature_died.faction == Creature.Faction.ALIEN:
		corpse_payload["finality_counter"] = INITIAL_FINALITY_FOR_NEW_CORPSES
	else: 
		corpse_payload["finality_counter"] = corpse_payload.get("current_finality_counter_on_death", 0)
		
	var new_corpse = CorpseData.new(corpse_payload)
	available_corpses.append(new_corpse)
	emit_signal("corpse_added", new_corpse)
	emit_signal("game_event_log_requested", "Corpse of %s appears (Finality: %d)." % [new_corpse.original_creature_name, new_corpse.finality_counter], "yellow") # Or white
	
	_remove_creature_from_game(creature_died, "died") # Pass reason for log

func _remove_creature_from_game(creature_to_remove: Creature, reason: String = "removed"):
	if not is_instance_valid(creature_to_remove): return
	
	var creature_name_for_log = creature_to_remove.creature_name
	var faction_str = Creature.Faction.keys()[creature_to_remove.faction]
	# Log is emitted by _on_creature_died if reason is "died"
	# For other reasons (e.g., "passed through", "returned to roster")
	if reason != "died": # Avoid double logging death
		emit_signal("game_event_log_requested", "%s '%s' %s from grid." % [faction_str, creature_name_for_log, reason], "red")

	if battle_grid_node.is_valid_grid_position(creature_to_remove.grid_pos):
		battle_grid_node.remove_creature_from(creature_to_remove.grid_pos)
		
	match creature_to_remove.faction:
		Creature.Faction.HUMAN: living_humans_on_grid.erase(creature_to_remove)
		Creature.Faction.ALIEN: living_aliens_on_grid.erase(creature_to_remove)
		Creature.Faction.UNDEAD:
			living_undead_on_grid.erase(creature_to_remove)
			if player_undead_roster.has(creature_to_remove): 
				player_undead_roster.erase(creature_to_remove)
				emit_signal("undead_roster_changed", player_undead_roster)
				
	if not creature_to_remove.is_queued_for_deletion():
		creature_to_remove.queue_free()

func consume_corpse(corpse: CorpseData): # Called by Reanimate spell
	if available_corpses.has(corpse):
		emit_signal("game_event_log_requested", "Corpse of %s consumed for reanimation." % corpse.original_creature_name, "red")
		available_corpses.erase(corpse)
		emit_signal("corpse_removed", corpse)

func _remove_corpse_from_list(corpse: CorpseData, reason: String = "removed"): 
	if available_corpses.has(corpse):
		emit_signal("game_event_log_requested", "Corpse of %s %s." % [corpse.original_creature_name, reason], "red")
		available_corpses.erase(corpse)
		emit_signal("corpse_removed", corpse)

# --- COMBAT RESOLUTION ---
func _resolve_combat_in_lane(col_idx: int) -> bool:
	var combat_occurred_this_lane = false
	while true: 
		var player_unit: Creature = null
		var alien_unit: Creature = null

		var player_rows_to_search = [
			battle_grid_node.get_player_row_y_by_faction_row_num(3), 
			battle_grid_node.get_player_row_y_by_faction_row_num(2), 
			battle_grid_node.get_player_row_y_by_faction_row_num(1)  
		]
		for r_y in player_rows_to_search:
			if r_y == -1: continue 
			var c = battle_grid_node.get_creature_at(Vector2i(col_idx, r_y))
			if is_instance_valid(c) and c.is_alive and (c.faction == Creature.Faction.HUMAN or c.faction == Creature.Faction.UNDEAD):
				player_unit = c; break 

		var alien_rows_to_search = [
			battle_grid_node.get_alien_row_y_by_faction_row_num(3), 
			battle_grid_node.get_alien_row_y_by_faction_row_num(2), 
			battle_grid_node.get_alien_row_y_by_faction_row_num(1)  
		]
		for r_y in alien_rows_to_search:
			if r_y == -1: continue
			var c = battle_grid_node.get_creature_at(Vector2i(col_idx, r_y))
			if is_instance_valid(c) and c.is_alive and c.faction == Creature.Faction.ALIEN:
				alien_unit = c; break 

		if not is_instance_valid(player_unit) or not is_instance_valid(alien_unit):
			break 

		combat_occurred_this_lane = true
		var p_name = player_unit.creature_name
		var a_name = alien_unit.creature_name
		var p_fac_str = Creature.Faction.keys()[player_unit.faction]
		var a_fac_str = Creature.Faction.keys()[alien_unit.faction]

		var alien_flew_over_this_combat = false
		if alien_unit.is_flying and not player_unit.is_flying and not player_unit.has_reach:
			emit_signal("game_event_log_requested", "%s '%s' flies over %s '%s'!" % [a_fac_str, a_name, p_fac_str, p_name], "yellow")
			_handle_alien_pass_through(alien_unit, "MidBattleFlyOver") # Emits log
			_remove_creature_from_game(alien_unit, "flew over") # Emits log
			alien_flew_over_this_combat = true
		
		if alien_flew_over_this_combat:
			continue 

		# Standard combat damage exchange
		var p_hp_old = player_unit.current_health
		var a_hp_old = alien_unit.current_health
		var p_ap = player_unit.attack_power
		var a_ap = alien_unit.attack_power

		# Player attacks Alien
		emit_signal("game_event_log_requested", "%s '%s' (AP:%d) attacks %s '%s' (HP:%d)." % [p_fac_str, p_name, p_ap, a_fac_str, a_name, a_hp_old], "yellow")
		alien_unit.take_damage(p_ap) 
		emit_signal("game_event_log_requested", " -> '%s' takes %d damage. HP: %d/%d." % [a_name, p_ap, alien_unit.current_health, alien_unit.max_health], "yellow")
		
		# Alien attacks Player (if still alive)
		if alien_unit.is_alive:
			emit_signal("game_event_log_requested", "%s '%s' (AP:%d) attacks %s '%s' (HP:%d)." % [a_fac_str, a_name, a_ap, p_fac_str, p_name, p_hp_old], "yellow")
			player_unit.take_damage(a_ap)
			emit_signal("game_event_log_requested", " -> '%s' takes %d damage. HP: %d/%d." % [p_name, a_ap, player_unit.current_health, player_unit.max_health], "yellow")

		if (is_instance_valid(player_unit) and not player_unit.is_alive) or \
		   (is_instance_valid(alien_unit) and not alien_unit.is_alive):
			pass # Deaths handled by signals, loop continues
		else:
			break # Both survived, end combat for this lane in this pass.
			
	return combat_occurred_this_lane

func _handle_alien_pass_through(alien: Creature, reason: String):
	if not is_instance_valid(alien): return
	var damage_to_population = alien.attack_power * 5 
	emit_signal("game_event_log_requested", "Alien '%s' (AP:%d) %s! Population -%d." % [alien.creature_name, alien.attack_power, reason, damage_to_population], "red")
	_set_human_civilian_population(human_civilian_population - damage_to_population)

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
	match undead.speed_type:
		Creature.SpeedType.SLOW: allowed_rows_y_coords = [p_row1_y] 
		Creature.SpeedType.NORMAL: allowed_rows_y_coords = [p_row1_y, p_row2_y] 
		Creature.SpeedType.FAST: allowed_rows_y_coords = [p_row1_y, p_row2_y, p_row3_y] 
	
	allowed_rows_y_coords = allowed_rows_y_coords.filter(func(y): return y != -1) 

	if not allowed_rows_y_coords.has(grid_pos.y) or not battle_grid_node.get_player_rows_indices().has(grid_pos.y) :
		emit_signal("game_event_log_requested", "Deploy Undead %s to %s failed. Not an allowed player row." % [undead.creature_name, str(grid_pos)], "yellow")
		return false

	if battle_grid_node.place_creature_at(undead, grid_pos):
		_add_creature_to_active_lists(undead) 
		emit_signal("game_event_log_requested", "Undead '%s' deployed from roster to %s." % [undead.creature_name, str(grid_pos)], "green")
		return true
	else:
		emit_signal("game_event_log_requested", "Failed to place Undead %s at %s (cell occupied/invalid)." % [undead.creature_name, str(grid_pos)], "yellow")
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
		living_undead_on_grid.erase(undead)
		if not player_undead_roster.has(undead): 
			player_undead_roster.append(undead)
		emit_signal("undead_roster_changed", player_undead_roster)
		undead.grid_pos = Vector2i(-1,-1) 
		emit_signal("game_event_log_requested", "Undead '%s' returned from %s to roster." % [undead.creature_name, str(old_pos)], "white")
		return true
	else:
		emit_signal("game_event_log_requested", "Failed to remove Undead %s from grid at %s." % [undead.creature_name, str(old_pos)], "yellow")
		if living_undead_on_grid.has(undead): living_undead_on_grid.erase(undead) 
		if not player_undead_roster.has(undead): player_undead_roster.append(undead) 
		emit_signal("undead_roster_changed", player_undead_roster) 
		return false
