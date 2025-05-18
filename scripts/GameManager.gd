# ./scripts/GameManager.gd
extends Node
class_name GameManager

# --- SIGNALS ---
signal turn_started(turn_number: int)
signal wave_started(wave_number: int, turn_number: int)
signal player_phase_started(phase_name: String) 
signal battle_phase_started
signal wave_ended(wave_number: int, turn_number: int) 
signal turn_finalized(turn_number: int) 

signal game_over(reason_key: String, message: String) 
signal human_population_changed(new_population: int)
signal corpse_added(corpse: CorpseData)
signal corpse_removed(corpse: CorpseData) 
signal undead_roster_changed(new_roster: Array[Creature]) 

signal game_event_log_requested(message: String, color_tag: String)


# --- GAME STATE ENUMS (Updated) ---
enum GamePhase { 
	NONE,                   
	OUT_OF_TURN,            
	TURN_STARTING,          
	TURN_AWAITING_FIRST_WAVE, 
	PLAYER_PRE_BATTLE,      
	BATTLE_IN_PROGRESS,     
	PLAYER_POST_BATTLE,     
	WAVE_CONCLUDED_AWAITING_NEXT, 
	TURN_ENDING_AWAIT_CONFIRM, 
	TURN_ENDING             
}

# --- CORE GAME VARIABLES ---
var current_turn: int = 0
var current_wave_in_turn: int = 0
var max_waves_per_turn: int = 3 
var waves_with_new_aliens: int = 2 
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
	# Emit player_phase_started so Game.gd updates the UI for the very start of the game
	emit_signal("player_phase_started", "OUT_OF_TURN")


# Player initiates turn start
func player_starts_new_turn():
	if current_game_phase != GamePhase.OUT_OF_TURN: return
	
	_change_game_phase(GamePhase.TURN_STARTING) 
	
	current_turn += 1
	current_wave_in_turn = 0 
	emit_signal("turn_started", current_turn) 
	
	if is_instance_valid(necromancer_node):
		necromancer_node.replenish_de_to_max() 
		
	_spawn_new_human_contingent() 
	
	_change_game_phase(GamePhase.TURN_AWAITING_FIRST_WAVE)
	emit_signal("player_phase_started", "TURN_AWAITING_FIRST_WAVE") 

# Player initiates wave start (first or subsequent)
func player_starts_wave():
	if current_game_phase != GamePhase.TURN_AWAITING_FIRST_WAVE and \
	   current_game_phase != GamePhase.WAVE_CONCLUDED_AWAITING_NEXT:
		return

	current_wave_in_turn += 1 
	
	if current_wave_in_turn > max_waves_per_turn and current_game_phase == GamePhase.WAVE_CONCLUDED_AWAITING_NEXT:
		# This case should ideally be prevented by UI button state, but as a fallback:
		emit_signal("game_event_log_requested", "Max waves for turn reached. Please end turn.", "yellow")
		# Force transition to end turn confirmation if somehow attempted
		_change_game_phase(GamePhase.TURN_ENDING_AWAIT_CONFIRM)
		emit_signal("player_phase_started", "TURN_ENDING_AWAIT_CONFIRM")
		return

	emit_signal("wave_started", current_wave_in_turn, current_turn) 
	
	if current_wave_in_turn <= waves_with_new_aliens: 
		_spawn_new_alien_wave()
		
	_change_game_phase(GamePhase.PLAYER_PRE_BATTLE) 
	emit_signal("player_phase_started", "PRE_BATTLE") 

# Player finishes pre-battle setup
func player_ends_pre_battle_phase():
	if current_game_phase != GamePhase.PLAYER_PRE_BATTLE: return
	emit_signal("game_event_log_requested", "Player ends pre-battle preparations for Wave %d." % current_wave_in_turn, "white")
	_initiate_battle_phase()

# Internal: Battle processing
func _initiate_battle_phase():
	_change_game_phase(GamePhase.BATTLE_IN_PROGRESS)
	emit_signal("battle_phase_started") 
	combat_log_for_gm_internal.clear() 
	
	for col_idx in range(battle_grid_node.GRID_COLUMNS):
		_resolve_combat_in_lane(col_idx)
		if human_civilian_population <= 0 and current_game_phase == GamePhase.NONE:
			return 
			
	_change_game_phase(GamePhase.PLAYER_POST_BATTLE)
	emit_signal("player_phase_started", "POST_BATTLE_REANIMATE")

# Player finishes post-battle actions
func player_ends_post_battle_phase():
	if current_game_phase != GamePhase.PLAYER_POST_BATTLE: return
	emit_signal("game_event_log_requested", "Player ends post-battle actions for Wave %d." % current_wave_in_turn, "white")
	_conclude_wave_processing()


# Internal: After player's post-battle actions, decide next step
func _conclude_wave_processing():
	emit_signal("wave_ended", current_wave_in_turn, current_turn) # Game.gd uses this for logging
	
	if human_civilian_population <= 0 and current_game_phase != GamePhase.NONE:
		return 

	var aliens_remain_on_grid = living_aliens_on_grid.size() > 0
	var all_configured_alien_waves_done = current_wave_in_turn >= waves_with_new_aliens
	
	if current_wave_in_turn >= max_waves_per_turn or \
	  (not aliens_remain_on_grid and all_configured_alien_waves_done):
		if not aliens_remain_on_grid and all_configured_alien_waves_done and current_wave_in_turn < max_waves_per_turn :
			emit_signal("game_event_log_requested", "All alien threats neutralized for this turn.", "green")
		_change_game_phase(GamePhase.TURN_ENDING_AWAIT_CONFIRM) 
		emit_signal("player_phase_started", "TURN_ENDING_AWAIT_CONFIRM") # UI update for "End Turn" button
	else:
		_change_game_phase(GamePhase.WAVE_CONCLUDED_AWAITING_NEXT) 
		emit_signal("player_phase_started", "WAVE_CONCLUDED_AWAITING_NEXT") # UI update for "Start Next Wave" button


# Player confirms ending the turn
func player_confirms_end_turn():
	if current_game_phase != GamePhase.TURN_ENDING_AWAIT_CONFIRM: return
	_finalize_turn_end_procedures()


# Internal: Final steps to end the turn
func _finalize_turn_end_procedures():
	_change_game_phase(GamePhase.TURN_ENDING) 
	
	for corpse_to_remove in available_corpses.duplicate(): 
		_remove_corpse_from_list(corpse_to_remove, "decayed at turn end") 
	
	emit_signal("turn_finalized", current_turn) 
	
	if current_turn >= 20 and human_civilian_population > 0: 
		_set_game_over("player_won", "Survived all turns!") 
		return

	if current_game_phase != GamePhase.NONE: 
		_change_game_phase(GamePhase.OUT_OF_TURN) 
		emit_signal("player_phase_started", "OUT_OF_TURN") # UI update for "Start Turn X+1" button


func _set_human_civilian_population(value: int):
	var old_pop = human_civilian_population
	human_civilian_population = max(0, value) 
	if old_pop != human_civilian_population:
		emit_signal("human_population_changed", human_civilian_population) 
		if human_civilian_population == 0 and current_game_phase != GamePhase.NONE: 
			_set_game_over("humans_extinct", "Human population reached zero.")

func _change_game_phase(new_phase: GamePhase):
	if current_game_phase != new_phase:
		# print_debug("GamePhase: %s -> %s (Turn: %d, Wave: %d)" % [GamePhase.keys()[current_game_phase], GamePhase.keys()[new_phase], current_turn, current_wave_in_turn])
		current_game_phase = new_phase

func _set_game_over(reason_key: String, message: String): 
	if current_game_phase == GamePhase.NONE and reason_key != "": return 
	_change_game_phase(GamePhase.NONE) 
	emit_signal("game_over", reason_key, message)

# --- UNIT SPAWNING AND MANAGEMENT ---
func _spawn_new_human_contingent():
	emit_signal("game_event_log_requested", "Human reinforcements arriving for Turn %d." % current_turn, "green")
	var humans_to_spawn: Array[Dictionary] = [
		{"type": "Human_Swordsman", "config": {"creature_name": "Swordsman", "level": 1, "max_health": 15, "attack_power": 4, "speed_type": Creature.SpeedType.NORMAL, "sprite_texture_path": "res://assets/images/placerholder_swordsman.png"}},
		{"type": "Human_Archer", "config": {"creature_name": "Archer", "level": 1, "max_health": 10, "attack_power": 3, "speed_type": Creature.SpeedType.NORMAL, "has_reach": true, "sprite_texture_path": "res://assets/images/placerholder_archer.png"}},
	]
	_auto_place_units(humans_to_spawn, Creature.Faction.HUMAN, "Human")

func _spawn_new_alien_wave():
	emit_signal("game_event_log_requested", "New alien wave %d (Turn %d) inbound!" % [current_wave_in_turn, current_turn], "red")
	var aliens_to_spawn: Array[Dictionary] = [
		{"type": "Alien_FireAnt", "config": {"creature_name": "FireAnt", "level": current_wave_in_turn, "max_health": 8 + current_wave_in_turn, "attack_power": 3 + (current_wave_in_turn / 2), "speed_type": Creature.SpeedType.FAST, "sprite_texture_path": "res://assets/images/placeholder_fireant.png"}},
		{"type": "Alien_Wasp", "config": {"creature_name": "Wasp", "level": current_wave_in_turn, "max_health": 6 + current_wave_in_turn, "attack_power": 2 + (current_wave_in_turn / 2), "speed_type": Creature.SpeedType.FAST, "is_flying": true, "sprite_texture_path": "res://assets/images/placeholder_wasp.png"}},
	]
	if current_wave_in_turn >= 2: 
		aliens_to_spawn.append({"type": "Alien_Beetle", "config": {"creature_name": "Beetle", "level": current_wave_in_turn, "max_health": 20 + (current_wave_in_turn * 2), "attack_power": 2 + current_wave_in_turn, "speed_type": Creature.SpeedType.SLOW, "sprite_texture_path": "res://assets/images/placeholder_beetle.png"}})
	
	_auto_place_units(aliens_to_spawn, Creature.Faction.ALIEN, "Alien")

func _auto_place_units(units_to_spawn_data: Array[Dictionary], faction: Creature.Faction, faction_name_for_log: String):
	if not is_instance_valid(battle_grid_node):
		printerr("GM: BattleGridNode not valid in _auto_place_units.")
		return
		
	var faction_rows_y_coords: Array[int] = [] 
	if faction == Creature.Faction.HUMAN or faction == Creature.Faction.UNDEAD: 
		faction_rows_y_coords = battle_grid_node.get_player_rows_indices().duplicate()
		faction_rows_y_coords.reverse()
	elif faction == Creature.Faction.ALIEN:
		faction_rows_y_coords = battle_grid_node.get_alien_rows_indices().duplicate()
		faction_rows_y_coords.reverse() 

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
	final_config["level"] = config_from_spell.get("level", 1) 
	
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
			if player_undead_roster.has(creature): 
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
	else: 
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
	
	if reason != "died": 
		emit_signal("game_event_log_requested", "%s '%s' (Lvl %d) %s from grid." % [faction_str, creature_name_for_log, creature_level_for_log, reason], "yellow")

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

func consume_corpse(corpse: CorpseData): 
	if available_corpses.has(corpse):
		emit_signal("game_event_log_requested", "Corpse of %s (Lvl %d) consumed for reanimation." % [corpse.original_creature_name, corpse.original_level], "white")
		available_corpses.erase(corpse)
		emit_signal("corpse_removed", corpse)

func _remove_corpse_from_list(corpse: CorpseData, reason: String = "removed"): 
	if available_corpses.has(corpse):
		emit_signal("game_event_log_requested", "Corpse of %s (Lvl %d) %s." % [corpse.original_creature_name, corpse.original_level, reason], "white")
		available_corpses.erase(corpse)
		emit_signal("corpse_removed", corpse)

# --- Helper Functions for Combat Resolution ---
func _find_foremost_player_defender(col_idx: int, rows_to_check: Array) -> Creature:
	for r_y in rows_to_check:
		if r_y == -1: continue
		var c = battle_grid_node.get_creature_at(Vector2i(col_idx, r_y))
		if is_instance_valid(c) and c.is_alive and (c.faction == Creature.Faction.HUMAN or c.faction == Creature.Faction.UNDEAD):
			return c
	return null

func _find_foremost_alien_attacker(col_idx: int, rows_to_check: Array, exclude_list: Array[Creature]) -> Creature:
	for r_y in rows_to_check:
		if r_y == -1: continue
		var c = battle_grid_node.get_creature_at(Vector2i(col_idx, r_y))
		if is_instance_valid(c) and c.is_alive and c.faction == Creature.Faction.ALIEN:
			if not c in exclude_list:
				return c
	return null

func _handle_alien_pass_through_action(alien_unit: Creature, reason_prefix: String):
	var damage = alien_unit.level * alien_unit.attack_power * randi_range(1, 10)
	var log_message = "%s '%s' (L%d AP%d) passed, dealing %d dmg to population." % [reason_prefix, alien_unit.creature_name, alien_unit.level, alien_unit.attack_power, damage]
	emit_signal("game_event_log_requested", log_message, "red")
	_set_human_civilian_population(human_civilian_population - damage)
	_remove_creature_from_game(alien_unit, reason_prefix.to_lower() + " and passed")


# --- COMBAT RESOLUTION (Pass-Through Rule Further Corrected) ---
func _resolve_combat_in_lane(col_idx: int) -> bool:
	var activity_in_lane = false 
	
	var player_rows_to_check_for_defender = [
		battle_grid_node.get_player_row_y_by_faction_row_num(3), 
		battle_grid_node.get_player_row_y_by_faction_row_num(2),
		battle_grid_node.get_player_row_y_by_faction_row_num(1)  
	]
	var alien_rows_to_check_for_attacker = [
		battle_grid_node.get_alien_row_y_by_faction_row_num(3), 
		battle_grid_node.get_alien_row_y_by_faction_row_num(2),
		battle_grid_node.get_alien_row_y_by_faction_row_num(1)  
	]

	var aliens_that_have_fought_this_wave_in_lane: Array[Creature] = []

	while true: 
		var player_unit = _find_foremost_player_defender(col_idx, player_rows_to_check_for_defender)
		var alien_unit = _find_foremost_alien_attacker(col_idx, alien_rows_to_check_for_attacker, aliens_that_have_fought_this_wave_in_lane)

		if not is_instance_valid(alien_unit):
			break 

		activity_in_lane = true

		if not is_instance_valid(player_unit):
			_handle_alien_pass_through_action(alien_unit, "Alien") 
			if human_civilian_population <= 0: return true 
			continue 

		var p_name = player_unit.creature_name; var p_lvl = player_unit.level
		var a_name = alien_unit.creature_name; var a_lvl = alien_unit.level
		var p_fac_str = Creature.Faction.keys()[player_unit.faction]
		var a_fac_str = Creature.Faction.keys()[alien_unit.faction]

		if alien_unit.is_flying and not player_unit.is_flying and not player_unit.has_reach:
			if alien_unit.grid_pos.y <= player_unit.grid_pos.y: 
				emit_signal("game_event_log_requested", "%s '%s' (L%d) flies over %s '%s' (L%d)!" % [a_fac_str, a_name, a_lvl, p_fac_str, p_name, p_lvl], "yellow")
				_handle_alien_pass_through_action(alien_unit, "Flying Alien") 
				if human_civilian_population <= 0: return true 
				continue 
		
		aliens_that_have_fought_this_wave_in_lane.append(alien_unit) 
		
		var p_hp_old = player_unit.current_health; var p_ap = player_unit.attack_power
		var a_hp_old = alien_unit.current_health; var a_ap = alien_unit.attack_power

		emit_signal("game_event_log_requested", "COMBAT: %s '%s' (L%d) vs %s '%s' (L%d) in col %d" % [p_fac_str, p_name, p_lvl, a_fac_str, a_name, a_lvl, col_idx], "white")

		if player_unit.can_attack_target(alien_unit):
			emit_signal("game_event_log_requested", " -> %s attacks %s (HP:%d)." % [p_name, a_name, a_hp_old], "white")
			alien_unit.take_damage(p_ap) 
			emit_signal("game_event_log_requested", "    L-> '%s' HP: %d/%d." % [a_name, alien_unit.current_health, alien_unit.max_health], "white")
		else:
			emit_signal("game_event_log_requested", " -> %s cannot attack %s." % [p_name, a_name], "gray")

		if alien_unit.is_alive: 
			if alien_unit.can_attack_target(player_unit):
				emit_signal("game_event_log_requested", " -> %s attacks %s (HP:%d)." % [a_name, p_name, p_hp_old], "white")
				player_unit.take_damage(a_ap)
				emit_signal("game_event_log_requested", "    L-> '%s' HP: %d/%d." % [p_name, player_unit.current_health, player_unit.max_health], "white")
			else:
				emit_signal("game_event_log_requested", " -> %s cannot attack %s." % [a_name, p_name], "gray")
		
		if player_unit.is_alive and alien_unit.is_alive:
			break 
		else:
			pass 
			
	return activity_in_lane


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
		living_undead_on_grid.erase(undead) 
		if not player_undead_roster.has(undead): 
			player_undead_roster.append(undead)
		emit_signal("undead_roster_changed", player_undead_roster)
		undead.grid_pos = Vector2i(-1,-1) 
		emit_signal("game_event_log_requested", "Undead '%s' (Lvl %d) returned from %s to roster." % [undead.creature_name, undead.level, str(old_pos)], "white")
		return true
	else:
		emit_signal("game_event_log_requested", "Failed to remove Undead %s (Lvl %d) from grid at %s during roster return." % [undead.creature_name, undead.level, str(old_pos)], "yellow")
		if living_undead_on_grid.has(undead): living_undead_on_grid.erase(undead) 
		if not player_undead_roster.has(undead): player_undead_roster.append(undead) 
		emit_signal("undead_roster_changed", player_undead_roster) 
		return false
