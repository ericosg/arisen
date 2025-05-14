# ./scripts/GameManager.gd
extends Node
class_name GameManager

# --- SIGNALS ---
signal turn_started(turn_number: int)
signal wave_started(wave_number: int, turn_number: int)
signal player_phase_started(phase_name: String) # e.g., "PRE_BATTLE", "REANIMATE_AFTER_WAVE"
signal battle_phase_started
signal wave_ended(wave_number: int, turn_number: int)
signal turn_ended(turn_number: int)
signal game_over(reason: String) # "humans_extinct", "player_won"
signal human_population_changed(new_population: int)
signal corpse_added(corpse: CorpseData)
signal corpse_removed(corpse: CorpseData)
signal undead_roster_changed(new_roster: Array[Creature]) # Pass the whole roster or specific changes

# --- GAME STATE ENUMS ---
enum GamePhase {
	NONE,
	OUT_OF_TURN,      # MC leveling, spell upgrades
	TURN_STARTING,    # Replenish DE, add humans
	PLAYER_PRE_BATTLE,# Player places units, casts non-combat spells
	BATTLE_IN_PROGRESS, # Combat resolution
	PLAYER_POST_BATTLE, # Player reanimates new corpses
	WAVE_ENDING,
	TURN_ENDING       # Alien pass-through, corpse decay
}

# --- CORE GAME VARIABLES ---
var current_turn: int = 0
var current_wave_in_turn: int = 0
var max_waves_per_turn: int = 5 # Example, can be dynamic
var waves_with_new_aliens: int = 3 # Example, aliens only spawn for first X waves

var human_civilian_population: int = 1000 : set = _set_human_civilian_population
const MAX_HUMAN_POPULATION: int = 1000 # Or loaded from config
const INITIAL_HUMAN_POPULATION: int = 1000

var current_game_phase: GamePhase = GamePhase.NONE

# --- PLAYER/NECROMANCER DATA ---
# Reference to the Necromancer node
var necromancer_node: Necromancer 

# --- CREATURE MANAGEMENT ---
# Lists to hold active creature nodes
var living_humans_on_grid: Array[Creature] = []
var living_aliens_on_grid: Array[Creature] = []
var living_undead_on_grid: Array[Creature] = [] # Player's undead currently on the battlefield

var player_undead_roster: Array[Creature] = [] # Undead not yet deployed, in the player's "pool"
var available_corpses: Array[CorpseData] = [] # List of CorpseData resources

# --- NODE REFERENCES ---
# These should be assigned when GameManager is ready, typically by a main "Game" scene.
var battle_grid_node: BattleGrid
var units_container_node: Node2D # A Node2D to parent all creature visual instances

# --- CONFIGURATION DATA (Paths to creature scripts/scenes if not using class_name directly) ---
# These would ideally be loaded from resources or a config file.
const CREATURE_SCRIPT_PATHS = {
	"Skeleton": "res://scripts/creatures/Skeleton.gd",
	"Zombie": "res://scripts/creatures/Zombie.gd",
	"Spirit": "res://scripts/creatures/Spirit.gd",
	"Human_Civilian": "res://scripts/creatures/Human.gd", # Assuming specific types use base Human.gd
	"Human_Swordsman": "res://scripts/creatures/Human.gd",
	"Human_Archer": "res://scripts/creatures/Human.gd",
	# Add Human_Knight if you have a specific config or it uses base Human.gd
	"Alien_FireAnt": "res://scripts/creatures/Alien.gd",
	"Alien_Wasp": "res://scripts/creatures/Alien.gd",
	"Alien_Spider": "res://scripts/creatures/Alien.gd", # Add missing alien types
	"Alien_Scorpion": "res://scripts/creatures/Alien.gd",
	"Alien_Beetle": "res://scripts/creatures/Alien.gd",
}
const INITIAL_FINALITY_FOR_NEW_CORPSES: int = 1 # When a living Human/Alien dies

# --- TEMPORARY STATE FOR COMBAT ---
var combat_log: Array[String] = [] # For storing messages during a battle phase

func _ready():
	# Initialization logic here
	# print_debug("GameManager ready.")
	# It's crucial that necromancer_node, battle_grid_node, and units_container_node are set
	# by the scene that instantiates GameManager before calling start_new_game() or similar.
	pass

# --- PUBLIC API / GAME CONTROL ---
func start_new_game():
	# print_debug("Starting new game...")
	current_turn = 0
	_set_human_civilian_population(INITIAL_HUMAN_POPULATION)
	
	# Clear all creature nodes from the units_container_node first
	for child in units_container_node.get_children():
		if child is Creature: # Or just queue_free all children if only creatures are there
			child.queue_free()

	living_humans_on_grid.clear()
	living_aliens_on_grid.clear()
	living_undead_on_grid.clear()
	player_undead_roster.clear()
	available_corpses.clear()
	
	if is_instance_valid(battle_grid_node): # Reset grid logical state
		battle_grid_node.initialize_grid_data() # Clears the grid_cells array
	
	if not is_instance_valid(necromancer_node):
		printerr("GameManager: Necromancer node not assigned! Cannot start game.")
		return
	if not is_instance_valid(battle_grid_node):
		printerr("GameManager: BattleGrid node not assigned! Cannot start game.")
		return
	if not is_instance_valid(units_container_node):
		printerr("GameManager: UnitsContainer node not assigned! Cannot start game.")
		return
		
	# Initialize Necromancer (e.g., reset level, DE, learn starting spells)
	# necromancer_node.initialize_for_new_game() # Needs method in Necromancer.gd
	necromancer_node.assign_runtime_references(self, battle_grid_node) # Give Necro refs to GM and BG

	_change_game_phase(GamePhase.OUT_OF_TURN)


func proceed_to_next_turn(): # Called by UI "Next Turn" button
	if current_game_phase != GamePhase.OUT_OF_TURN and current_game_phase != GamePhase.TURN_ENDING and current_game_phase != GamePhase.NONE:
		printerr("GameManager: Cannot proceed to next turn from phase: %s" % GamePhase.keys()[current_game_phase])
		return
	
	current_turn += 1
	current_wave_in_turn = 0
	# print_debug("--- Starting Turn %d ---" % current_turn)
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
		printerr("GameManager: Cannot start next wave from phase: %s" % GamePhase.keys()[current_game_phase])
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
	if current_game_phase != GamePhase.PLAYER_PRE_BATTLE:
		printerr("GameManager: Cannot start battle from phase: %s" % GamePhase.keys()[current_game_phase])
		return
	
	_initiate_battle_phase()

func _initiate_battle_phase():
	_change_game_phase(GamePhase.BATTLE_IN_PROGRESS)
	emit_signal("battle_phase_started")
	combat_log.clear()
	
	var any_combat_occurred = false
	for col_idx in range(battle_grid_node.GRID_COLUMNS):
		if _resolve_combat_in_lane(col_idx):
			any_combat_occurred = true
			
	_change_game_phase(GamePhase.PLAYER_POST_BATTLE)
	emit_signal("player_phase_started", "POST_BATTLE_REANIMATE")


func player_ends_post_battle_phase(): 
	if current_game_phase != GamePhase.PLAYER_POST_BATTLE:
		printerr("GameManager: Cannot end post-battle phase from: %s" % GamePhase.keys()[current_game_phase])
		return
	
	_end_current_wave()


func _end_current_wave():
	emit_signal("wave_ended", current_wave_in_turn, current_turn)
	_change_game_phase(GamePhase.WAVE_ENDING)

	var aliens_remaining_on_grid = living_aliens_on_grid.size() > 0
	var more_aliens_to_spawn_this_turn = current_wave_in_turn < waves_with_new_aliens
	
	if not aliens_remaining_on_grid and not more_aliens_to_spawn_this_turn:
		_end_current_turn()
	else:
		# Game waits for player to click "Next Wave" (which calls proceed_to_next_wave)
		# or if max_waves_per_turn is hit, proceed_to_next_wave will call _end_current_turn
		pass 


func _end_current_turn():
	_change_game_phase(GamePhase.TURN_ENDING)
	
	var aliens_that_passed_this_turn: Array[Creature] = []
	# Iterate over a copy for safe removal
	for alien in living_aliens_on_grid.duplicate(): 
		if not is_instance_valid(alien) or not alien.is_alive: continue
		
		var lane_is_clear_for_alien = true
		for player_unit in living_humans_on_grid + living_undead_on_grid:
			if is_instance_valid(player_unit) and player_unit.is_alive and player_unit.grid_pos.x == alien.grid_pos.x:
				lane_is_clear_for_alien = false
				break
		
		if lane_is_clear_for_alien:
			aliens_that_passed_this_turn.append(alien)
			
	for alien_passed in aliens_that_passed_this_turn:
		_handle_alien_pass_through(alien_passed, "End of Turn Survivor")
		if is_instance_valid(alien_passed): 
			_remove_creature_from_game(alien_passed)

	var corpses_to_remove = available_corpses.duplicate() 
	for corpse_data in corpses_to_remove:
		_remove_corpse_from_list(corpse_data) 
	available_corpses.clear() 

	emit_signal("turn_ended", current_turn)
	
	if current_turn >= 20: # Example win condition
		_set_game_over("player_won", "Survived 20 turns!")
		return

	_change_game_phase(GamePhase.OUT_OF_TURN)


# --- SETTERS ---
func _set_human_civilian_population(value: int):
	var old_pop = human_civilian_population
	human_civilian_population = max(0, value) 
	if old_pop != human_civilian_population:
		emit_signal("human_population_changed", human_civilian_population)
		if human_civilian_population == 0:
			_set_game_over("humans_extinct", "Human civilian population reached zero.")

# --- GAME PHASE MANAGEMENT ---
func _change_game_phase(new_phase: GamePhase):
	if current_game_phase != new_phase:
		current_game_phase = new_phase


func _set_game_over(reason_key: String, message: String):
	if current_game_phase == GamePhase.NONE and reason_key != "": # Avoid multiple game over calls unless resetting
		return 
	
	_change_game_phase(GamePhase.NONE) 
	emit_signal("game_over", reason_key)


# --- CREATURE SPAWNING & MANAGEMENT ---
func _spawn_new_human_contingent():
	# Explicitly type the array as Array[Dictionary]
	var humans_to_spawn: Array[Dictionary] = [
		{"type": "Human_Swordsman", "config": {"creature_name": "Swordsman", "max_health": 15, "attack_power": 4, "speed_type": Creature.SpeedType.NORMAL}},
		{"type": "Human_Archer", "config": {"creature_name": "Archer", "max_health": 10, "attack_power": 3, "speed_type": Creature.SpeedType.NORMAL, "has_reach": true}},
		{"type": "Human_Civilian", "config": {"creature_name": "Civilian", "max_health": 5, "attack_power": 0, "speed_type": Creature.SpeedType.SLOW}},
	]
	_auto_place_units(humans_to_spawn, Creature.Faction.HUMAN)

func _spawn_new_alien_wave():
	# Explicitly type the array as Array[Dictionary]
	var aliens_to_spawn: Array[Dictionary] = [
		{"type": "Alien_FireAnt", "config": {"creature_name": "FireAnt", "max_health": 8, "attack_power": 3, "speed_type": Creature.SpeedType.FAST}},
		{"type": "Alien_Wasp", "config": {"creature_name": "Wasp", "max_health": 6, "attack_power": 2, "speed_type": Creature.SpeedType.FAST, "is_flying": true}},
	]
	if current_wave_in_turn == 2: 
		aliens_to_spawn.append({"type": "Alien_Beetle", "config": {"creature_name": "Beetle", "max_health": 20, "attack_power": 2, "speed_type": Creature.SpeedType.SLOW}})

	_auto_place_units(aliens_to_spawn, Creature.Faction.ALIEN)

# Function signature already expects Array[Dictionary]
func _auto_place_units(units_to_spawn_data: Array[Dictionary], faction: Creature.Faction):
	# GDD Auto-Placement: Center, first row, then push forward rows, then expand columns.
	# This is a complex logic. For now, simplified L-R in preferred rows.
	# TODO: Implement the full GDD auto-placement logic.
	
	var faction_rows_y_coords: Array[int]
	if faction == Creature.Faction.HUMAN:
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
	else: return

	for unit_data in units_to_spawn_data:
		var creature_node: Creature = _create_creature_node_from_config(unit_data["type"], unit_data["config"], faction)
		if not is_instance_valid(creature_node): continue

		var placed = false
		# Try to place in faction's Row 1, then Row 2, then Row 3 (L-R in each row)
		for row_y in faction_rows_y_coords: 
			var target_pos = battle_grid_node.find_first_empty_cell_in_row(row_y)
			if target_pos != Vector2i(-1,-1):
				if battle_grid_node.place_creature_at(creature_node, target_pos):
					_add_creature_to_active_lists(creature_node)
					creature_node.position = battle_grid_node.get_world_position_for_grid_cell_center(target_pos)
					placed = true
					break 
		if not placed:
			creature_node.queue_free()


func spawn_reanimated_creature(creature_config_from_spell: Dictionary) -> Creature:
	var script_path = creature_config_from_spell.get("creature_class_script_path", "")
	if script_path == "":
		printerr("GameManager: No creature_class_script_path in config for reanimation.")
		return null

	var creature_node = Node2D.new() 
	var creature_script = load(script_path)
	if not creature_script:
		printerr("GameManager: Failed to load creature script at %s" % script_path)
		creature_node.queue_free()
		return null
	
	creature_node.set_script(creature_script)
	
	var actual_creature_instance: Creature = creature_node as Creature 
	if not is_instance_valid(actual_creature_instance): 
		printerr("GameManager: Node did not become a Creature after script attach.")
		creature_node.queue_free()
		return null

	actual_creature_instance.game_manager = self
	actual_creature_instance.battle_grid = battle_grid_node
	
	actual_creature_instance.initialize_creature(creature_config_from_spell)
	
	units_container_node.add_child(actual_creature_instance)
	
	player_undead_roster.append(actual_creature_instance)
	emit_signal("undead_roster_changed", player_undead_roster)
	
	return actual_creature_instance


func _create_creature_node_from_config(creature_type_key: String, config_data: Dictionary, faction_override: Creature.Faction) -> Creature:
	var script_path = CREATURE_SCRIPT_PATHS.get(creature_type_key, "")
	if script_path == "":
		printerr("GameManager: No script path found for creature type key '%s'." % creature_type_key)
		return null

	var creature_node = Node2D.new()
	var creature_script = load(script_path)
	if not creature_script:
		printerr("GameManager: Failed to load creature script at %s for type %s" % [script_path, creature_type_key])
		creature_node.queue_free()
		return null
	
	creature_node.set_script(creature_script)
	
	var actual_creature_instance: Creature = creature_node as Creature
	if not is_instance_valid(actual_creature_instance):
		printerr("GameManager: Node did not become a Creature for type %s." % creature_type_key)
		creature_node.queue_free()
		return null
		
	actual_creature_instance.game_manager = self
	actual_creature_instance.battle_grid = battle_grid_node
	
	var final_config = config_data.duplicate(true)
	final_config["faction"] = faction_override 
	
	actual_creature_instance.initialize_creature(final_config)
	units_container_node.add_child(actual_creature_instance)
	
	if not actual_creature_instance.died.is_connected(_on_creature_died): 
		actual_creature_instance.died.connect(_on_creature_died.bind(actual_creature_instance))
	
	return actual_creature_instance

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


func _on_creature_died(creature_that_died: Creature):
	if not is_instance_valid(creature_that_died):
		return
	
	var corpse_payload = creature_that_died.get_data_for_corpse_creation()
	corpse_payload["grid_pos_on_death"] = creature_that_died.grid_pos
	corpse_payload["turn_of_death"] = current_turn
	
	if creature_that_died.faction == Creature.Faction.HUMAN or creature_that_died.faction == Creature.Faction.ALIEN:
		corpse_payload["finality_counter"] = INITIAL_FINALITY_FOR_NEW_CORPSES
	else: 
		corpse_payload["finality_counter"] = corpse_payload.get("current_finality_counter_on_death", 0)

	var new_corpse = CorpseData.new(corpse_payload)
	available_corpses.append(new_corpse)
	emit_signal("corpse_added", new_corpse)

	_remove_creature_from_game(creature_that_died)


func _remove_creature_from_game(creature_to_remove: Creature):
	if not is_instance_valid(creature_to_remove): return

	if battle_grid_node.is_valid_grid_position(creature_to_remove.grid_pos):
		battle_grid_node.remove_creature_from(creature_to_remove.grid_pos)

	match creature_to_remove.faction:
		Creature.Faction.HUMAN:
			if living_humans_on_grid.has(creature_to_remove): living_humans_on_grid.erase(creature_to_remove)
		Creature.Faction.ALIEN:
			if living_aliens_on_grid.has(creature_to_remove): living_aliens_on_grid.erase(creature_to_remove)
		Creature.Faction.UNDEAD:
			if living_undead_on_grid.has(creature_to_remove): living_undead_on_grid.erase(creature_to_remove)
			if player_undead_roster.has(creature_to_remove): 
				player_undead_roster.erase(creature_to_remove) 
				emit_signal("undead_roster_changed", player_undead_roster)

	if is_instance_valid(creature_to_remove) and not creature_to_remove.is_queued_for_deletion():
		creature_to_remove.queue_free()

func consume_corpse(corpse_to_consume: CorpseData): 
	if available_corpses.has(corpse_to_consume):
		available_corpses.erase(corpse_to_consume)
		emit_signal("corpse_removed", corpse_to_consume)

func _remove_corpse_from_list(corpse_data: CorpseData): 
	if available_corpses.has(corpse_data):
		available_corpses.erase(corpse_data)
		emit_signal("corpse_removed", corpse_data)


# --- COMBAT LOGIC ---
func _resolve_combat_in_lane(column_index: int) -> bool:
	var combat_this_lane = false
	
	while true: 
		var front_player_unit: Creature = null
		var front_alien_unit: Creature = null
		
		# Find front-most player unit
		for r_idx_player in range(battle_grid_node.GRID_ROWS_PER_FACTION - 1, -1, -1): 
			var creature_p = battle_grid_node.get_creature_at(Vector2i(column_index, r_idx_player))
			if is_instance_valid(creature_p) and creature_p.is_alive and \
			   (creature_p.faction == Creature.Faction.HUMAN or creature_p.faction == Creature.Faction.UNDEAD):
				front_player_unit = creature_p
				break
		
		# Find front-most Alien unit
		for r_idx_alien in range(battle_grid_node.GRID_ROWS_PER_FACTION, battle_grid_node.TOTAL_GRID_ROWS): 
			var creature_a = battle_grid_node.get_creature_at(Vector2i(column_index, r_idx_alien))
			if is_instance_valid(creature_a) and creature_a.is_alive and creature_a.faction == Creature.Faction.ALIEN:
				front_alien_unit = creature_a
				break
		
		if not is_instance_valid(front_player_unit) or not is_instance_valid(front_alien_unit):
			break 

		combat_this_lane = true
		var log_entry = "Lane %d: %s vs %s" % [column_index, front_player_unit.creature_name, front_alien_unit.creature_name]
		
		var alien_passed_through = false
		if front_alien_unit.is_flying and not front_player_unit.is_flying and not front_player_unit.has_reach:
			log_entry += " - ALIEN PASSES (Unblockable)!"
			combat_log.append(log_entry)
			_handle_alien_pass_through(front_alien_unit, "Mid-battle Unblockable")
			_remove_creature_from_game(front_alien_unit) 
			alien_passed_through = true
		
		if alien_passed_through:
			continue 

		# Direct Combat
		var p_hp_before = front_player_unit.current_health
		var a_hp_before = front_alien_unit.current_health

		front_player_unit.take_damage(front_alien_unit.attack_power)
		front_alien_unit.take_damage(front_player_unit.attack_power)

		log_entry += " | P: %d->%d HP | A: %d->%d HP" % [p_hp_before, front_player_unit.current_health, a_hp_before, front_alien_unit.current_health]
		combat_log.append(log_entry)
		
		if not front_player_unit.is_alive and not front_alien_unit.is_alive: break 
		if not front_player_unit.is_alive or not front_alien_unit.is_alive: pass # One died

	return combat_this_lane

func _handle_alien_pass_through(alien_creature: Creature, reason: String):
	if not is_instance_valid(alien_creature): return
	
	var damage_to_civilians = alien_creature.attack_power * 5 
	_set_human_civilian_population(human_civilian_population - damage_to_civilians)
	# The calling function (_resolve_combat_in_lane or _end_current_turn)
	# is responsible for calling _remove_creature_from_game for the passed alien.

# --- UTILITY / GETTER METHODS for other scripts ---
func get_available_corpses() -> Array[CorpseData]:
	return available_corpses 

func get_all_living_humans_and_aliens() -> Array[Creature]:
	var combined_list: Array[Creature] = []
	combined_list.append_array(living_humans_on_grid)
	combined_list.append_array(living_aliens_on_grid)
	return combined_list.filter(func(c: Creature): return is_instance_valid(c) and c.is_alive)

func get_player_undead_roster() -> Array[Creature]:
	return player_undead_roster

# --- PLAYER ACTIONS (called by UI or Input Handler) ---
func player_deploys_undead_from_roster(undead_in_roster: Creature, target_grid_pos: Vector2i) -> bool:
	if current_game_phase != GamePhase.PLAYER_PRE_BATTLE: return false
	if not is_instance_valid(undead_in_roster) or not player_undead_roster.has(undead_in_roster): return false
	
	var player_rows_y = [
		battle_grid_node.get_player_row_y_by_faction_row_num(1), 
		battle_grid_node.get_player_row_y_by_faction_row_num(2), 
		battle_grid_node.get_player_row_y_by_faction_row_num(3)  
	]
	var allowed_rows_for_speed: Array[int] = []
	match undead_in_roster.speed_type:
		Creature.SpeedType.SLOW: allowed_rows_for_speed = [player_rows_y[0]]
		Creature.SpeedType.NORMAL: allowed_rows_for_speed = [player_rows_y[0], player_rows_y[1]]
		Creature.SpeedType.FAST: allowed_rows_for_speed = player_rows_y
	
	if not target_grid_pos.y in allowed_rows_for_speed: return false

	if battle_grid_node.place_creature_at(undead_in_roster, target_grid_pos):
		_add_creature_to_active_lists(undead_in_roster) 
		undead_in_roster.position = battle_grid_node.get_world_position_for_grid_cell_center(target_grid_pos)
		return true
	return false

func player_returns_undead_to_roster(undead_on_grid: Creature) -> bool:
	if current_game_phase != GamePhase.PLAYER_PRE_BATTLE: return false
	if not is_instance_valid(undead_on_grid) or not living_undead_on_grid.has(undead_on_grid): return false
		
	var original_pos = undead_on_grid.grid_pos
	if battle_grid_node.remove_creature_from(original_pos) == undead_on_grid: 
		living_undead_on_grid.erase(undead_on_grid)
		player_undead_roster.append(undead_on_grid)
		emit_signal("undead_roster_changed", player_undead_roster)
		undead_on_grid.grid_pos = Vector2i(-1,-1) 
		return true
	return false

func late_initialize_references(necro_node: Necromancer, bg_node: BattleGrid, units_container: Node2D):
	necromancer_node = necro_node
	battle_grid_node = bg_node
	units_container_node = units_container
	
	# battle_grid_node.assign_runtime_references(self) # Only if BG needs GM ref
