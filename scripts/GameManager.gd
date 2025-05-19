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
# MODIFIED: corpse_added now also passes the Creature node that became the corpse visual
signal corpse_added(corpse_data: CorpseData, corpse_node: Creature) 
signal corpse_removed(corpse_data: CorpseData) # When CorpseData resource is consumed/decayed
signal undead_roster_changed(new_roster: Array[Creature]) 
signal game_event_log_requested(message: String, color_tag: String)
signal unit_deployed_to_grid(creature: Creature, grid_pos: Vector2i) # For Game.gd drag cleanup
signal unit_move_on_grid_completed(creature: Creature, new_grid_pos: Vector2i) # For Game.gd drag cleanup


# --- GAME STATE ENUMS ---
# Using your existing GamePhase enum from the provided GameManager.gd
enum GamePhase { 
	NONE, OUT_OF_TURN, TURN_STARTING, TURN_AWAITING_FIRST_WAVE, 
	PLAYER_PRE_BATTLE, BATTLE_IN_PROGRESS, PLAYER_POST_BATTLE, 
	WAVE_CONCLUDED_AWAITING_NEXT, TURN_ENDING_AWAIT_CONFIRM, TURN_ENDING             
}

# --- CORE GAME VARIABLES ---
var current_turn: int = 0
var current_wave_in_turn: int = 0
var max_waves_per_turn: int = 3 # Your value
var waves_with_new_aliens: int = 2 # Your value
var human_civilian_population: int = 1000 : set = _set_human_civilian_population
const INITIAL_HUMAN_POPULATION: int = 1000
var current_game_phase: GamePhase = GamePhase.NONE

# --- ENTITY MANAGEMENT ---
var living_humans_on_grid: Array[Creature] = []
var living_aliens_on_grid: Array[Creature] = []
var living_undead_on_grid: Array[Creature] = [] 
var player_undead_roster: Array[Creature] = []  # Stores actual Creature node instances for the pool
var available_corpses: Array[CorpseData] = []  # Stores CorpseData resources (the data, not the visual node)

# --- NODE REFERENCES ---
var necromancer_node: Necromancer
var battle_grid_node: BattleGrid
var units_container_node: Node2D # Parent for units ON THE BATTLE GRID

# --- CONFIGURATION ---
# Using your existing CREATURE_SCRIPT_PATHS
const CREATURE_SCRIPT_PATHS = {
	"Skeleton": "res://scripts/creatures/Skeleton.gd", "Zombie": "res://scripts/creatures/Zombie.gd",
	"Spirit": "res://scripts/creatures/Spirit.gd", "Human_Civilian": "res://scripts/creatures/Human.gd", 
	"Human_Swordsman": "res://scripts/creatures/Human.gd", "Human_Archer": "res://scripts/creatures/Human.gd",
	"Human_Knight": "res://scripts/creatures/Human.gd", "Alien_FireAnt": "res://scripts/creatures/Alien.gd",
	"Alien_Wasp": "res://scripts/creatures/Alien.gd", "Alien_Beetle": "res://scripts/creatures/Alien.gd",
}
const INITIAL_FINALITY_FOR_NEW_CORPSES: int = 1 


func _ready():
	randomize()

func late_initialize_references(necro: Necromancer, bg: BattleGrid, units_cont: Node2D):
	necromancer_node = necro
	battle_grid_node = bg
	units_container_node = units_cont 
	if is_instance_valid(battle_grid_node): battle_grid_node.assign_runtime_references(self) 
	if is_instance_valid(necromancer_node): necromancer_node.assign_runtime_references(self, battle_grid_node)

# --- GAME FLOW CONTROL (Using your existing refined flow) ---
func start_new_game():
	current_turn = 0; _set_human_civilian_population(INITIAL_HUMAN_POPULATION) 
	for child in units_container_node.get_children(): # Clear units from battle grid
		if child is Creature: child.queue_free()
	
	living_humans_on_grid.clear(); living_aliens_on_grid.clear(); living_undead_on_grid.clear()
	
	for creature_node in player_undead_roster: # Clear undead from roster pool
		if is_instance_valid(creature_node): creature_node.queue_free()
	player_undead_roster.clear()
	emit_signal("undead_roster_changed", player_undead_roster) # Notify display to clear
	
	available_corpses.clear() 
	
	if is_instance_valid(battle_grid_node): battle_grid_node.initialize_grid_data() 
	if not (is_instance_valid(necromancer_node) and is_instance_valid(battle_grid_node) and is_instance_valid(units_container_node)):
		printerr("GM: Critical node missing at start_new_game!"); get_tree().quit(); return
	_change_game_phase(GamePhase.OUT_OF_TURN); emit_signal("player_phase_started", "OUT_OF_TURN")

func player_starts_new_turn(): # Copied from your version
	if current_game_phase != GamePhase.OUT_OF_TURN: return
	_change_game_phase(GamePhase.TURN_STARTING) 
	current_turn += 1; current_wave_in_turn = 0 
	emit_signal("turn_started", current_turn) 
	if is_instance_valid(necromancer_node): necromancer_node.replenish_de_to_max() 
	_spawn_new_human_contingent() 
	_change_game_phase(GamePhase.TURN_AWAITING_FIRST_WAVE); emit_signal("player_phase_started", "TURN_AWAITING_FIRST_WAVE") 

func player_starts_wave(): # Copied from your version
	if not (current_game_phase == GamePhase.TURN_AWAITING_FIRST_WAVE or current_game_phase == GamePhase.WAVE_CONCLUDED_AWAITING_NEXT): return
	current_wave_in_turn += 1 
	if current_wave_in_turn > max_waves_per_turn and current_game_phase == GamePhase.WAVE_CONCLUDED_AWAITING_NEXT:
		emit_signal("game_event_log_requested", "Max waves for turn reached. End turn.", "yellow")
		_change_game_phase(GamePhase.TURN_ENDING_AWAIT_CONFIRM); emit_signal("player_phase_started", "TURN_ENDING_AWAIT_CONFIRM")
		return
	emit_signal("wave_started", current_wave_in_turn, current_turn) 
	if current_wave_in_turn <= waves_with_new_aliens: _spawn_new_alien_wave()
	_change_game_phase(GamePhase.PLAYER_PRE_BATTLE); emit_signal("player_phase_started", "PRE_BATTLE") 

func player_ends_pre_battle_phase(): # Copied
	if current_game_phase != GamePhase.PLAYER_PRE_BATTLE: return
	emit_signal("game_event_log_requested", "Player ends pre-battle for Wave %d." % current_wave_in_turn, "white")
	_initiate_battle_phase()

func _initiate_battle_phase(): # Copied
	_change_game_phase(GamePhase.BATTLE_IN_PROGRESS); emit_signal("battle_phase_started") 
	for col_idx in range(battle_grid_node.GRID_COLUMNS):
		_resolve_combat_in_lane(col_idx)
		if human_civilian_population <= 0 and current_game_phase == GamePhase.NONE: return 
	_change_game_phase(GamePhase.PLAYER_POST_BATTLE); emit_signal("player_phase_started", "POST_BATTLE_REANIMATE")

func player_ends_post_battle_phase(): # Copied
	if current_game_phase != GamePhase.PLAYER_POST_BATTLE: return
	emit_signal("game_event_log_requested", "Player ends post-battle for Wave %d." % current_wave_in_turn, "white")
	_conclude_wave_processing()

func _conclude_wave_processing(): # Copied
	emit_signal("wave_ended", current_wave_in_turn, current_turn) 
	if human_civilian_population <= 0 and current_game_phase != GamePhase.NONE: return 
	var aliens_remain = living_aliens_on_grid.size() > 0
	var all_waves_spawned = current_wave_in_turn >= waves_with_new_aliens
	if current_wave_in_turn >= max_waves_per_turn or (not aliens_remain and all_waves_spawned):
		if not aliens_remain and all_waves_spawned and current_wave_in_turn < max_waves_per_turn :
			emit_signal("game_event_log_requested", "All alien threats neutralized for turn.", "green")
		_change_game_phase(GamePhase.TURN_ENDING_AWAIT_CONFIRM); emit_signal("player_phase_started", "TURN_ENDING_AWAIT_CONFIRM")
	else:
		_change_game_phase(GamePhase.WAVE_CONCLUDED_AWAITING_NEXT); emit_signal("player_phase_started", "WAVE_CONCLUDED_AWAITING_NEXT")

func player_confirms_end_turn(): # Copied
	if current_game_phase != GamePhase.TURN_ENDING_AWAIT_CONFIRM: return
	_finalize_turn_end_procedures()

func _finalize_turn_end_procedures(): # MODIFIED for corpse node cleanup
	_change_game_phase(GamePhase.TURN_ENDING) 
	
	# Decay CorpseData and remove visual corpse nodes from grid
	for corpse_data_item in available_corpses.duplicate(): # Iterate copy
		var corpse_node_on_grid = battle_grid_node.get_corpse_node_at(corpse_data_item.grid_pos_on_death)
		if is_instance_valid(corpse_node_on_grid):
			# Remove from BattleGrid's internal array and visual parent
			battle_grid_node.remove_creature_from(corpse_data_item.grid_pos_on_death) 
			if corpse_node_on_grid.get_parent() == units_container_node: # Ensure it's the one on grid
				corpse_node_on_grid.queue_free() # Free the visual node
			
		_remove_corpse_data_from_list(corpse_data_item, "decayed at turn end") # Removes CorpseData from available_corpses
	
	emit_signal("turn_finalized", current_turn) 
	if current_turn >= 20 and human_civilian_population > 0: _set_game_over("player_won", "Survived all turns!"); return
	if current_game_phase != GamePhase.NONE: 
		_change_game_phase(GamePhase.OUT_OF_TURN); emit_signal("player_phase_started", "OUT_OF_TURN")

func _set_human_civilian_population(value: int): # Copied
	var old_pop = human_civilian_population; human_civilian_population = max(0, value) 
	if old_pop != human_civilian_population:
		emit_signal("human_population_changed", human_civilian_population) 
		if human_civilian_population == 0 and current_game_phase != GamePhase.NONE: 
			_set_game_over("humans_extinct", "Human population zero.")
func _change_game_phase(new_phase: GamePhase): # Copied
	if current_game_phase != new_phase: current_game_phase = new_phase
func _set_game_over(reason: String, msg: String): # Copied
	if current_game_phase == GamePhase.NONE and reason != "": return 
	_change_game_phase(GamePhase.NONE); emit_signal("game_over", reason, msg)

# --- UNIT SPAWNING AND MANAGEMENT ---
func _spawn_new_human_contingent(): # Using your existing structure
	emit_signal("game_event_log_requested", "Human reinforcements arriving for Turn %d." % current_turn, "green")
	var humans_to_spawn_configs: Array[Dictionary] = [
		{"type": "Human_Swordsman", "config": {"creature_name": "Swordsman", "level": 1, "max_health": 15, "attack_power": 4, "speed_type": Creature.SpeedType.NORMAL, "sprite_texture_path": "res://assets/images/placerholder_swordsman.png", "corpse_texture_path": "res://assets/images/corpse_human.png"}},
		{"type": "Human_Archer", "config": {"creature_name": "Archer", "level": 1, "max_health": 10, "attack_power": 3, "speed_type": Creature.SpeedType.NORMAL, "has_reach": true, "sprite_texture_path": "res://assets/images/placerholder_archer.png", "corpse_texture_path": "res://assets/images/corpse_human.png"}},
	]
	_auto_place_units(humans_to_spawn_configs, Creature.Faction.HUMAN, "Human")

func _spawn_new_alien_wave(): # Using your existing structure
	emit_signal("game_event_log_requested", "New alien wave %d (Turn %d) inbound!" % [current_wave_in_turn, current_turn], "red")
	var aliens_to_spawn_configs: Array[Dictionary] = [
		{"type": "Alien_FireAnt", "config": {"creature_name": "FireAnt", "level": current_wave_in_turn, "max_health": 8 + current_wave_in_turn, "attack_power": 3 + (current_wave_in_turn / 2), "speed_type": Creature.SpeedType.FAST, "sprite_texture_path": "res://assets/images/placeholder_fireant.png", "corpse_texture_path": "res://assets/images/corpse_alien.png"}},
		{"type": "Alien_Wasp", "config": {"creature_name": "Wasp", "level": current_wave_in_turn, "max_health": 6 + current_wave_in_turn, "attack_power": 2 + (current_wave_in_turn / 2), "speed_type": Creature.SpeedType.FAST, "is_flying": true, "sprite_texture_path": "res://assets/images/placeholder_wasp.png", "corpse_texture_path": "res://assets/images/corpse_alien.png"}},
	]
	if current_wave_in_turn >= 2: 
		aliens_to_spawn_configs.append({"type": "Alien_Beetle", "config": {"creature_name": "Beetle", "level": current_wave_in_turn, "max_health": 20 + (current_wave_in_turn * 2), "attack_power": 2 + current_wave_in_turn, "speed_type": Creature.SpeedType.SLOW, "sprite_texture_path": "res://assets/images/placeholder_beetle.png", "corpse_texture_path": "res://assets/images/corpse_alien.png"}})
	_auto_place_units(aliens_to_spawn_configs, Creature.Faction.ALIEN, "Alien")

func _auto_place_units(unit_data_list: Array[Dictionary], faction: Creature.Faction, log_name: String): # Adapted
	for unit_data in unit_data_list:
		var creature_node = _create_creature_node_from_config_data(unit_data["type"], unit_data["config"], faction)
		if not is_instance_valid(creature_node): continue
		
		var placed = false
		var rows_to_try = battle_grid_node.get_player_rows_indices().duplicate() if faction != Creature.Faction.ALIEN else battle_grid_node.get_alien_rows_indices().duplicate()
		rows_to_try.reverse() # Try front rows first for placement
		
		for r_y in rows_to_try:
			if r_y == -1: continue 
			var target_pos = battle_grid_node.find_first_empty_cell_in_row(r_y) # Checks for LIVING units
			if target_pos != Vector2i(-1,-1):
				if _place_newly_spawned_unit(creature_node, target_pos): # Places on grid and adds to lists
					emit_signal("game_event_log_requested", "%s '%s' (L%d) deployed at %s." % [log_name, creature_node.creature_name, creature_node.level, str(target_pos)], "green")
					placed = true; break
		if not placed:
			emit_signal("game_event_log_requested", "Could not place %s '%s'." % [log_name, unit_data["config"].creature_name], "yellow")
			creature_node.queue_free()

func _place_newly_spawned_unit(creature: Creature, grid_pos: Vector2i) -> bool:
	units_container_node.add_child(creature) # Add to scene tree BEFORE placing on grid
	if battle_grid_node.place_creature_at(creature, grid_pos): # This handles corpse "underneath"
		_add_creature_to_active_lists(creature)
		return true
	else: 
		units_container_node.remove_child(creature); creature.queue_free() # Cleanup if placement failed
		return false

# MODIFIED: Reanimated undead go to roster, not directly to grid.
func spawn_reanimated_creature(config_from_spell: Dictionary, _grid_pos_on_death_hint: Vector2i) -> Creature: 
	var creature_config_data = config_from_spell.duplicate(true) # Use the full config
	# Ensure faction is Undead, and get type for script path
	creature_config_data["faction"] = Creature.Faction.UNDEAD 
	var creature_type_key = config_from_spell.get("creature_type_key_for_script", "Skeleton") # Expect this in payload from spell
	
	# Level for reanimated could be based on corpse's original level or spell level
	creature_config_data["level"] = config_from_spell.get("original_level", 1) # Use original level from corpse data

	var actual_creature = _create_creature_node_from_config_data(creature_type_key, creature_config_data, Creature.Faction.UNDEAD)
	
	if is_instance_valid(actual_creature):
		# Set finality based on what ReanimateSpellData calculated
		actual_creature.finality_counter = config_from_spell.get("finality_counter", 0)

		player_undead_roster.append(actual_creature) # Add to roster (node is NOT parented to scene yet)
		emit_signal("undead_roster_changed", player_undead_roster) # UndeadPoolDisplay will pick this up
		emit_signal("game_event_log_requested", "Reanimated '%s' (L%d, F%d) added to Undead Pool." % [actual_creature.creature_name, actual_creature.level, actual_creature.finality_counter], "green")
		return actual_creature
	return null

# MODIFIED: To use full config data directly, similar to your existing spawn logic
func _create_creature_node_from_config_data(type_key: String, config_data: Dictionary, faction_override: Creature.Faction) -> Creature:
	var script_path = CREATURE_SCRIPT_PATHS.get(type_key, "")
	if script_path == "":
		printerr("GM: No script path defined for creature type_key: %s" % type_key)
		return null
	
	var creature_node_base = Node2D.new()
	var sprite_node = Sprite2D.new(); sprite_node.name = "Sprite"; creature_node_base.add_child(sprite_node)
	
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
	
	var final_cfg = config_data.duplicate(true) # Use the provided config
	final_cfg["faction"] = faction_override # Ensure correct faction
	
	actual_creature.initialize_creature(final_cfg) # Creature.gd sets up sprite from path in config
	# DO NOT add to units_container_node here. That's done by the placer functions or deploy from pool.
	
	# Connect died signal if not already connected (important for creatures created outside _auto_place_units)
	if not actual_creature.died.is_connected(_on_creature_died):
		actual_creature.died.connect(_on_creature_died)
		
	return actual_creature

func _add_creature_to_active_lists(creature: Creature): # For units on the battle grid
	if not is_instance_valid(creature) or creature.is_corpse: return
	match creature.faction:
		Creature.Faction.HUMAN: if not living_humans_on_grid.has(creature): living_humans_on_grid.append(creature)
		Creature.Faction.ALIEN: if not living_aliens_on_grid.has(creature): living_aliens_on_grid.append(creature)
		Creature.Faction.UNDEAD: if not living_undead_on_grid.has(creature): living_undead_on_grid.append(creature)
			# If it was deployed from roster, GameManager.player_deploys_undead_from_roster handles roster removal.

func _on_creature_died(dying_creature_node: Creature): # dying_creature_node is the visual node that just died
	if not is_instance_valid(dying_creature_node): return
	
	# Creature.die() already changed its sprite and set is_corpse = true.
	# It remains on the grid as a visual corpse.
	
	var faction_str = Creature.Faction.keys()[dying_creature_node.faction]
	emit_signal("game_event_log_requested", "%s '%s' (L%d) has fallen at %s, becoming a corpse." % [faction_str, dying_creature_node.creature_name, dying_creature_node.level, str(dying_creature_node.grid_pos)], "red")

	var corpse_payload = dying_creature_node.get_data_for_corpse_creation() 
	corpse_payload["grid_pos_on_death"] = dying_creature_node.grid_pos # Ensure this is set
	corpse_payload["turn_of_death"] = current_turn
	if dying_creature_node.faction == Creature.Faction.HUMAN or dying_creature_node.faction == Creature.Faction.ALIEN:
		corpse_payload["finality_counter"] = INITIAL_FINALITY_FOR_NEW_CORPSES
	else: # Undead that died
		corpse_payload["finality_counter"] = corpse_payload.get("current_finality_counter_on_death", 0)
		
	var new_corpse_data_resource = CorpseData.new(corpse_payload) # This is the Resource
	available_corpses.append(new_corpse_data_resource)
	
	# Signal that CorpseData is available AND pass the Creature node that is now the visual corpse
	emit_signal("corpse_added", new_corpse_data_resource, dying_creature_node) 
	emit_signal("game_event_log_requested", "Corpse of %s (L%d) available. Finality: %d." % [new_corpse_data_resource.original_creature_name, new_corpse_data_resource.original_level, new_corpse_data_resource.finality_counter], "yellow")
	
	# Remove from active LIVING lists, but the node itself (now a corpse visual) remains on the grid
	# and in BattleGrid.grid_cells until explicitly removed or replaced.
	match dying_creature_node.faction:
		Creature.Faction.HUMAN: living_humans_on_grid.erase(dying_creature_node)
		Creature.Faction.ALIEN: living_aliens_on_grid.erase(dying_creature_node)
		Creature.Faction.UNDEAD: living_undead_on_grid.erase(dying_creature_node)

func _remove_creature_from_game(creature_to_remove: Creature, reason: String = "removed"): # For LIVING units that are *not* becoming corpses
	if not is_instance_valid(creature_to_remove) or creature_to_remove.is_corpse: return 
	
	var log_name = creature_to_remove.creature_name; var log_lvl = creature_to_remove.level
	var log_fac = Creature.Faction.keys()[creature_to_remove.faction]
	if reason != "died": emit_signal("game_event_log_requested", "%s '%s' (L%d) %s." % [log_fac, log_name, log_lvl, reason], "yellow")

	if battle_grid_node.is_valid_grid_position(creature_to_remove.grid_pos):
		battle_grid_node.remove_creature_from(creature_to_remove.grid_pos) # Removes from grid_cells
	
	match creature_to_remove.faction:
		Creature.Faction.HUMAN: living_humans_on_grid.erase(creature_to_remove)
		Creature.Faction.ALIEN: living_aliens_on_grid.erase(creature_to_remove)
		Creature.Faction.UNDEAD: living_undead_on_grid.erase(creature_to_remove)
				
	if creature_to_remove.get_parent() == units_container_node: 
		creature_to_remove.queue_free()
	# If it's from roster and removed for other reasons, roster management handles freeing.

func consume_corpse_data_for_reanimation(corpse_data_to_consume: CorpseData): 
	if available_corpses.has(corpse_data_to_consume):
		emit_signal("game_event_log_requested", "Corpse of %s (L%d) consumed for reanimation." % [corpse_data_to_consume.original_creature_name, corpse_data_to_consume.original_level], "white")
		
		var corpse_visual_node = battle_grid_node.get_corpse_node_at(corpse_data_to_consume.grid_pos_on_death)
		if is_instance_valid(corpse_visual_node):
			battle_grid_node.remove_creature_from(corpse_data_to_consume.grid_pos_on_death) # Clears from grid_cells
			if corpse_visual_node.get_parent() == units_container_node:
				corpse_visual_node.queue_free() # Free the visual node
			
		available_corpses.erase(corpse_data_to_consume) # Remove the CorpseData resource
		emit_signal("corpse_removed", corpse_data_to_consume)

func _remove_corpse_data_from_list(corpse_data: CorpseData, reason: String = "removed"): # Internal helper
	if available_corpses.has(corpse_data):
		# The visual node cleanup is handled by _finalize_turn_end_procedures or consume_corpse_data
		emit_signal("game_event_log_requested", "Corpse data for %s (L%d) %s." % [corpse_data.original_creature_name, corpse_data.original_level, reason], "white")
		available_corpses.erase(corpse_data)
		emit_signal("corpse_removed", corpse_data)

# --- COMBAT RESOLUTION (Using your existing refined logic) ---
# ... (Your _find_foremost_player_defender, _find_foremost_alien_attacker, _handle_alien_pass_through_action, _resolve_combat_in_lane are good) ...
# Ensure they use battle_grid_node.get_living_creature_at() if they only care about living units for combat.

func _find_foremost_player_defender(col_idx: int) -> Creature:
	var rows_to_check = [ # Player front to back
		battle_grid_node.get_player_row_y_by_faction_row_num(3), 
		battle_grid_node.get_player_row_y_by_faction_row_num(2),
		battle_grid_node.get_player_row_y_by_faction_row_num(1)  
	]
	for r_y in rows_to_check:
		if r_y == -1: continue
		var c = battle_grid_node.get_living_creature_at(Vector2i(col_idx, r_y)) # Check for LIVING
		if is_instance_valid(c) and (c.faction == Creature.Faction.HUMAN or c.faction == Creature.Faction.UNDEAD):
			return c
	return null

func _find_foremost_alien_attacker(col_idx: int, exclude_list: Array[Creature]) -> Creature:
	var rows_to_check = [ # Alien front to back
		battle_grid_node.get_alien_row_y_by_faction_row_num(3), 
		battle_grid_node.get_alien_row_y_by_faction_row_num(2),
		battle_grid_node.get_alien_row_y_by_faction_row_num(1)  
	]
	for r_y in rows_to_check:
		if r_y == -1: continue
		var c = battle_grid_node.get_living_creature_at(Vector2i(col_idx, r_y)) # Check for LIVING
		if is_instance_valid(c) and c.faction == Creature.Faction.ALIEN and not c in exclude_list:
			return c
	return null

func _handle_alien_pass_through_action(alien_unit: Creature, reason_prefix: String): # Your version
	var damage = alien_unit.level * alien_unit.attack_power * randi_range(1, 10)
	emit_signal("game_event_log_requested", "%s '%s' (L%d AP%d) passed, dealing %d dmg to pop." % [reason_prefix, alien_unit.creature_name, alien_unit.level, alien_unit.attack_power, damage], "red")
	_set_human_civilian_population(human_civilian_population - damage)
	_remove_creature_from_game(alien_unit, reason_prefix.to_lower() + " (passed)") # This will q_free

func _resolve_combat_in_lane(col_idx: int): # Your version, ensure it uses LIVING creatures for combat checks
	var aliens_that_have_acted_this_wave: Array[Creature] = []
	while true: 
		var player_unit = _find_foremost_player_defender(col_idx) # Finds living defender
		var alien_unit = _find_foremost_alien_attacker(col_idx, aliens_that_have_acted_this_wave) # Finds living alien
		if not is_instance_valid(alien_unit): break 

		if not is_instance_valid(player_unit): 
			_handle_alien_pass_through_action(alien_unit, "Unblocked Alien") 
			if human_civilian_population <= 0: return 
			aliens_that_have_acted_this_wave.append(alien_unit) 
			continue 

		if alien_unit.is_flying and not player_unit.is_flying and not player_unit.has_reach and alien_unit.grid_pos.y <= player_unit.grid_pos.y:
			emit_signal("game_event_log_requested", "Flying Alien '%s' (L%d) flies over %s '%s' (L%d)!" % [alien_unit.creature_name, alien_unit.level, player_unit.creature_name, player_unit.level], "yellow")
			_handle_alien_pass_through_action(alien_unit, "Flying Alien")
			if human_civilian_population <= 0: return
			aliens_that_have_acted_this_wave.append(alien_unit) 
			continue
		
		aliens_that_have_acted_this_wave.append(alien_unit) 
		emit_signal("game_event_log_requested", "COMBAT: %s (L%d) vs %s (L%d)" % [player_unit.creature_name, player_unit.level, alien_unit.creature_name, alien_unit.level], "white")
		if player_unit.can_attack_target(alien_unit): alien_unit.take_damage(player_unit.attack_power)
		if alien_unit.is_alive and alien_unit.can_attack_target(player_unit): player_unit.take_damage(alien_unit.attack_power)
		
		if not player_unit.is_alive or not alien_unit.is_alive: continue 
		else: break 

# --- PLAYER ACTIONS (Placeholders for now, to be implemented in Phase 3) ---
func player_deploys_undead_from_roster(_creature_to_deploy: Creature, _target_grid_pos: Vector2i) -> bool:
	emit_signal("game_event_log_requested", "DEBUG: Deploy from roster called (not fully implemented).", "gray")
	return false 
func player_moves_ally_on_grid(_creature_to_move: Creature, _new_target_grid_pos: Vector2i) -> bool:
	emit_signal("game_event_log_requested", "DEBUG: Move ally on grid called (not fully implemented).", "gray")
	return false
# func _is_valid_deployment_row_for_speed... (will be needed in Phase 3)

# --- UTILITY / GETTER METHODS ---
func get_available_corpses() -> Array[CorpseData]: # Returns CorpseData resources
	return available_corpses.filter(func(cd): return is_instance_valid(cd) and cd.can_be_reanimated())

func get_corpse_data_at_grid_pos(grid_pos: Vector2i) -> CorpseData:
	"""Finds CorpseData whose original death location matches grid_pos."""
	for corpse_data_item in available_corpses:
		if corpse_data_item.grid_pos_on_death == grid_pos:
			return corpse_data_item
	return null

func get_all_living_humans_and_aliens() -> Array[Creature]: # Your version
	var all: Array[Creature] = []; all.append_array(living_humans_on_grid.filter(func(c): return is_instance_valid(c) and c.is_alive))
	all.append_array(living_aliens_on_grid.filter(func(c): return is_instance_valid(c) and c.is_alive)); return all
func get_player_undead_roster() -> Array[Creature]: # Returns Creature nodes
	return player_undead_roster.filter(func(c): return is_instance_valid(c)) 
