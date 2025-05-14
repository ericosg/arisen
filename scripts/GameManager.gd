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
	"Alien_FireAnt": "res://scripts/creatures/Alien.gd",
	"Alien_Wasp": "res://scripts/creatures/Alien.gd",
	# Add all creature types and their script paths
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
	
	living_humans_on_grid.clear()
	living_aliens_on_grid.clear()
	living_undead_on_grid.clear()
	player_undead_roster.clear()
	available_corpses.clear()
	
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

	# TODO: Player can level up MC, spells (Out-of-Turn Phase)
	_change_game_phase(GamePhase.OUT_OF_TURN)
	# For now, let's jump straight to starting the first turn after a brief moment or UI interaction
	# proceed_to_next_turn() # This would be called by UI later

func proceed_to_next_turn(): # Called by UI "Next Turn" button
	if current_game_phase != GamePhase.OUT_OF_TURN and current_game_phase != GamePhase.TURN_ENDING and current_game_phase != GamePhase.NONE:
		printerr("GameManager: Cannot proceed to next turn from phase: %s" % GamePhase.keys()[current_game_phase])
		return
	
	current_turn += 1
	current_wave_in_turn = 0
	# print_debug("--- Starting Turn %d ---" % current_turn)
	emit_signal("turn_started", current_turn)
	_change_game_phase(GamePhase.TURN_STARTING)
	
	# 1. Replenish Necromancer's DE
	if is_instance_valid(necromancer_node):
		necromancer_node.replenish_de_to_max()
		
	# 2. Add new Human units (auto-placement)
	_spawn_new_human_contingent()
	
	# Transition to the first wave's pre-battle phase
	proceed_to_next_wave()

func proceed_to_next_wave(): # Called by UI "Start Next Wave" or "End Player Phase" button
	if current_game_phase != GamePhase.TURN_STARTING and \
	   current_game_phase != GamePhase.PLAYER_POST_BATTLE and \
	   current_game_phase != GamePhase.WAVE_ENDING: # Can also come from wave ending naturally
		printerr("GameManager: Cannot start next wave from phase: %s" % GamePhase.keys()[current_game_phase])
		return

	current_wave_in_turn += 1
	if current_wave_in_turn > max_waves_per_turn:
		# print_debug("Max waves for turn %d reached. Ending turn." % current_turn)
		_end_current_turn()
		return

	# print_debug("--- Starting Wave %d (Turn %d) ---" % [current_wave_in_turn, current_turn])
	emit_signal("wave_started", current_wave_in_turn, current_turn)
	
	# 3. Add new Alien units (auto-placement, if applicable for this wave)
	if current_wave_in_turn <= waves_with_new_aliens:
		_spawn_new_alien_wave()
		
	# 4. Player Pre-Battle Phase
	_change_game_phase(GamePhase.PLAYER_PRE_BATTLE)
	emit_signal("player_phase_started", "PRE_BATTLE")
	# UI should now allow player to place units from roster, cast spells.
	# Player clicks "Start Battle" button when ready.

func player_ends_pre_battle_phase(): # Called by UI "Start Battle" button
	if current_game_phase != GamePhase.PLAYER_PRE_BATTLE:
		printerr("GameManager: Cannot start battle from phase: %s" % GamePhase.keys()[current_game_phase])
		return
	
	# print_debug("Player ends pre-battle phase. Starting battle...")
	_initiate_battle_phase()

func _initiate_battle_phase():
	_change_game_phase(GamePhase.BATTLE_IN_PROGRESS)
	emit_signal("battle_phase_started")
	combat_log.clear()
	
	# --- COMBAT RESOLUTION ---
	var any_combat_occurred = false
	for col_idx in range(battle_grid_node.GRID_COLUMNS):
		if _resolve_combat_in_lane(col_idx):
			any_combat_occurred = true
			
	# print_debug("Battle phase concluded.")
	# print_debug("Combat Log:\n" + "\n".join(combat_log)) # Optional: display combat log

	# After battle, move to player's post-battle phase (reanimation)
	_change_game_phase(GamePhase.PLAYER_POST_BATTLE)
	emit_signal("player_phase_started", "POST_BATTLE_REANIMATE")
	# UI allows player to reanimate newly created corpses.
	# Player clicks "End Wave" or "Next Wave" button when ready.

func player_ends_post_battle_phase(): # Called by UI "End Wave" or "Proceed" button
	if current_game_phase != GamePhase.PLAYER_POST_BATTLE:
		printerr("GameManager: Cannot end post-battle phase from: %s" % GamePhase.keys()[current_game_phase])
		return
	
	# print_debug("Player ends post-battle (reanimation) phase.")
	_end_current_wave()


func _end_current_wave():
	# print_debug("--- Ending Wave %d (Turn %d) ---" % [current_wave_in_turn, current_turn])
	emit_signal("wave_ended", current_wave_in_turn, current_turn)
	_change_game_phase(GamePhase.WAVE_ENDING)

	# Check if there are any more aliens or if combat is possible.
	# If no aliens left on grid and no more spawning this turn, or no possible engagements,
	# the turn might end early.
	var aliens_remaining_on_grid = living_aliens_on_grid.size() > 0
	var more_aliens_to_spawn_this_turn = current_wave_in_turn < waves_with_new_aliens
	
	if not aliens_remaining_on_grid and not more_aliens_to_spawn_this_turn:
		# print_debug("No aliens left and no more to spawn this turn. Ending turn early.")
		_end_current_turn()
	else:
		# Proceed to the next wave normally (player will click "Next Wave")
		# The game is now waiting for player to click "Next Wave" which calls proceed_to_next_wave()
		# Or, if max waves reached, this will also lead to _end_current_turn() via proceed_to_next_wave()
		pass


func _end_current_turn():
	# print_debug("--- Ending Turn %d ---" % current_turn)
	_change_game_phase(GamePhase.TURN_ENDING)
	
	# 1. Alien "Pass Through" for survivors
	var aliens_that_passed_this_turn: Array[Creature] = []
	for alien in living_aliens_on_grid: # Iterate over a copy if modifying list
		if not is_instance_valid(alien) or not alien.is_alive: continue
		
		var lane_is_clear_for_alien = true
		# Check if any player units are in the same column as this alien
		for player_unit in living_humans_on_grid + living_undead_on_grid:
			if is_instance_valid(player_unit) and player_unit.is_alive and player_unit.grid_pos.x == alien.grid_pos.x:
				lane_is_clear_for_alien = false
				break
		
		if lane_is_clear_for_alien:
			aliens_that_passed_this_turn.append(alien)
			
	for alien_passed in aliens_that_passed_this_turn:
		_handle_alien_pass_through(alien_passed, "End of Turn Survivor")
		# Remove from grid and active list (done by _handle_alien_pass_through if it queues_free)
		# If not, ensure removal here:
		if is_instance_valid(alien_passed): # Check if it wasn't already removed
			_remove_creature_from_game(alien_passed)

	# 2. Corpse Decay: Remove all corpses from available_corpses list
	# print_debug("Decaying all remaining corpses at end of turn.")
	var corpses_to_remove = available_corpses.duplicate() # Iterate over copy
	for corpse_data in corpses_to_remove:
		_remove_corpse_from_list(corpse_data) # Emits signal
	available_corpses.clear() # Ensure list is empty

	emit_signal("turn_ended", current_turn)
	
	# Check win/loss conditions (e.g., if current_turn == MAX_TURNS_FOR_VICTORY)
	if current_turn >= 20: # Example win condition
		_set_game_over("player_won", "Survived 20 turns!")
		return

	# Transition to Out-of-Turn phase for player upgrades, then player clicks "Next Turn"
	_change_game_phase(GamePhase.OUT_OF_TURN)


# --- SETTERS ---
func _set_human_civilian_population(value: int):
	var old_pop = human_civilian_population
	human_civilian_population = max(0, value) # Cannot go below 0
	if old_pop != human_civilian_population:
		emit_signal("human_population_changed", human_civilian_population)
		# print_debug("Human civilian population changed to: %d" % human_civilian_population)
		if human_civilian_population == 0:
			_set_game_over("humans_extinct", "Human civilian population reached zero.")

# --- GAME PHASE MANAGEMENT ---
func _change_game_phase(new_phase: GamePhase):
	if current_game_phase != new_phase:
		# print_debug("GamePhase changing from %s to %s" % [GamePhase.keys()[current_game_phase], GamePhase.keys()[new_phase]])
		current_game_phase = new_phase
		# Emit a signal for broader game state changes if needed by UI
		# emit_signal("game_phase_changed", new_phase)


func _set_game_over(reason_key: String, message: String):
	if current_game_phase == GamePhase.NONE: return # Avoid multiple game over calls if already over
	
	# print_debug("GAME OVER: %s" % message)
	_change_game_phase(GamePhase.NONE) # Or a specific GAME_OVER phase
	emit_signal("game_over", reason_key)
	# Here you would typically disable further game input, show a game over screen, etc.


# --- CREATURE SPAWNING & MANAGEMENT ---
func _spawn_new_human_contingent():
	# Example: Spawn 3 Swordsmen
	var humans_to_spawn = [
		{"type": "Human_Swordsman", "config": {"creature_name": "Swordsman", "max_health": 15, "attack_power": 4, "speed_type": Creature.SpeedType.NORMAL}},
		{"type": "Human_Archer", "config": {"creature_name": "Archer", "max_health": 10, "attack_power": 3, "speed_type": Creature.SpeedType.NORMAL, "has_reach": true}},
		{"type": "Human_Civilian", "config": {"creature_name": "Civilian", "max_health": 5, "attack_power": 0, "speed_type": Creature.SpeedType.SLOW}},
	]
	# GDD Auto-Placement: Center, first row, then push forward rows, then expand columns.
	_auto_place_units(humans_to_spawn, Creature.Faction.HUMAN)

func _spawn_new_alien_wave():
	# Example: Spawn a mix of aliens
	var aliens_to_spawn = [
		{"type": "Alien_FireAnt", "config": {"creature_name": "FireAnt", "max_health": 8, "attack_power": 3, "speed_type": Creature.SpeedType.FAST}},
		{"type": "Alien_Wasp", "config": {"creature_name": "Wasp", "max_health": 6, "attack_power": 2, "speed_type": Creature.SpeedType.FAST, "is_flying": true}},
	]
	if current_wave_in_turn == 2: # More aliens on wave 2
		aliens_to_spawn.append({"type": "Alien_Beetle", "config": {"creature_name": "Beetle", "max_health": 20, "attack_power": 2, "speed_type": Creature.SpeedType.SLOW}})

	_auto_place_units(aliens_to_spawn, Creature.Faction.ALIEN)

func _auto_place_units(units_to_spawn_data: Array[Dictionary], faction: Creature.Faction):
	# Implements GDD auto-placement: Center, first row, then fill rows in center cols, then expand cols.
	var starting_cols_indices: Array[int] = []
	var num_units = units_to_spawn_data.size()

	# Determine starting center columns (simplified)
	# For 8 columns: C,D,E are 2,3,4. D,E are 3,4. E is 4.
	if num_units == 0: return
	if num_units == 1:
		starting_cols_indices = [battle_grid_node.GRID_COLUMNS / 2] # Col D or E if even/odd
	elif num_units == 2:
		starting_cols_indices = [battle_grid_node.GRID_COLUMNS / 2 - 1, battle_grid_node.GRID_COLUMNS / 2] # C,D or D,E
	elif num_units >= 3: # C,D,E then expand
		starting_cols_indices = [
			battle_grid_node.GRID_COLUMNS / 2 - 1, 
			battle_grid_node.GRID_COLUMNS / 2, 
			battle_grid_node.GRID_COLUMNS / 2 + 1
		]
	# This centering needs refinement for perfect balance and expansion for more than 3 units.
	# For now, let's use a simpler left-to-right fill for the example batch.

	var current_unit_idx = 0
	var faction_rows: Array[int]
	if faction == Creature.Faction.HUMAN:
		faction_rows = [
			battle_grid_node.get_player_row_y_by_faction_row_num(1), # Player Row 1 (bottom)
			battle_grid_node.get_player_row_y_by_faction_row_num(2),
			battle_grid_node.get_player_row_y_by_faction_row_num(3)  # Player Row 3 (front)
		]
	elif faction == Creature.Faction.ALIEN:
		faction_rows = [
			battle_grid_node.get_alien_row_y_by_faction_row_num(1), # Alien Row 1 (top)
			battle_grid_node.get_alien_row_y_by_faction_row_num(2),
			battle_grid_node.get_alien_row_y_by_faction_row_num(3)  # Alien Row 3 (front)
		]
	else: return # Should not happen

	# GDD: "always starting from the center and first rows and always push forward before occupying new columns."
	# This is complex. For now, a simpler L-R fill in preferred rows for demonstration.
	# Proper implementation of GDD centering and "push forward rows then expand columns" is needed.
	
	# Simplified placement: Fill first available row, L-R for now.
	var preferred_row_y = faction_rows[0] # Faction's "Row 1"
	
	for unit_data in units_to_spawn_data:
		var creature_node: Creature = _create_creature_node_from_config(unit_data["type"], unit_data["config"], faction)
		if not is_instance_valid(creature_node): continue

		# Find empty cell in preferred_row_y, then next row, etc.
		var placed = false
		for row_y in faction_rows: # Try Row 1, then Row 2, then Row 3 for the faction
			var target_pos = battle_grid_node.find_first_empty_cell_in_row(row_y)
			if target_pos != Vector2i(-1,-1):
				if battle_grid_node.place_creature_at(creature_node, target_pos):
					_add_creature_to_active_lists(creature_node)
					# Set visual position if units_container_node is used
					creature_node.position = battle_grid_node.get_world_position_for_grid_cell_center(target_pos)
					placed = true
					break
		if not placed:
			# print_debug("Could not place %s; no empty cells in designated rows." % creature_node.creature_name)
			creature_node.queue_free() # Clean up unplaced creature


# Called by ReanimateSpell
func spawn_reanimated_creature(creature_config_from_spell: Dictionary) -> Creature:
	var script_path = creature_config_from_spell.get("creature_class_script_path", "")
	if script_path == "":
		printerr("GameManager: No creature_class_script_path in config for reanimation.")
		return null

	var creature_node = Node2D.new() # Base node for visuals
	var creature_script = load(script_path)
	if not creature_script:
		printerr("GameManager: Failed to load creature script at %s" % script_path)
		creature_node.queue_free()
		return null
	
	creature_node.set_script(creature_script)
	
	# Now that script is attached, it IS a Creature (or Undead, Skeleton etc.)
	var actual_creature_instance: Creature = creature_node as Creature 
	if not is_instance_valid(actual_creature_instance): # Should not happen if script loaded
		printerr("GameManager: Node did not become a Creature after script attach.")
		creature_node.queue_free()
		return null

	# Assign references the creature might need
	actual_creature_instance.game_manager = self
	actual_creature_instance.battle_grid = battle_grid_node
	
	# Initialize with the full config (name, stats, finality, etc.)
	actual_creature_instance.initialize_creature(creature_config_from_spell)
	
	units_container_node.add_child(actual_creature_instance)
	
	# Add to player's Undead Roster (not directly to grid)
	player_undead_roster.append(actual_creature_instance)
	emit_signal("undead_roster_changed", player_undead_roster)
	# print_debug("Reanimated %s (Finality: %d) added to roster." % [actual_creature_instance.creature_name, actual_creature_instance.finality_counter])
	
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
	
	# Ensure faction from config_data is overridden by faction_override (e.g. for Human/Alien spawns)
	var final_config = config_data.duplicate(true)
	final_config["faction"] = faction_override 
	
	actual_creature_instance.initialize_creature(final_config)
	units_container_node.add_child(actual_creature_instance)
	
	# Connect to its 'died' signal
	if not actual_creature_instance.died.is_connected(_on_creature_died): # Avoid duplicate connections
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
			# If it was in roster, remove it (assuming it's now on grid)
			if player_undead_roster.has(creature):
				player_undead_roster.erase(creature)
				emit_signal("undead_roster_changed", player_undead_roster)

# Called when a creature's 'died' signal is emitted
func _on_creature_died(creature_that_died: Creature):
	if not is_instance_valid(creature_that_died):
		return

	# print_debug("GameManager: Detected death of %s at %s" % [creature_that_died.creature_name, str(creature_that_died.grid_pos)])
	
	# 1. Create CorpseData resource
	var corpse_payload = creature_that_died.get_data_for_corpse_creation()
	corpse_payload["grid_pos_on_death"] = creature_that_died.grid_pos
	corpse_payload["turn_of_death"] = current_turn
	
	# Assign initial finality if it was a living Human/Alien
	if creature_that_died.faction == Creature.Faction.HUMAN or creature_that_died.faction == Creature.Faction.ALIEN:
		corpse_payload["finality_counter"] = INITIAL_FINALITY_FOR_NEW_CORPSES
	else: # It was Undead, its own finality is already in the payload
		corpse_payload["finality_counter"] = corpse_payload.get("current_finality_counter_on_death", 0)

	var new_corpse = CorpseData.new(corpse_payload)
	available_corpses.append(new_corpse)
	emit_signal("corpse_added", new_corpse)
	# print_debug("Corpse created for %s. Finality: %d" % [new_corpse.original_creature_name, new_corpse.finality_counter])

	# 2. Remove creature from grid and active lists
	_remove_creature_from_game(creature_that_died)


func _remove_creature_from_game(creature_to_remove: Creature):
	if not is_instance_valid(creature_to_remove): return

	# print_debug("GameManager: Removing %s from game." % creature_to_remove.creature_name)
	# Remove from BattleGrid
	if battle_grid_node.is_valid_grid_position(creature_to_remove.grid_pos):
		battle_grid_node.remove_creature_from(creature_to_remove.grid_pos) # Emits cell_vacated

	# Remove from active lists
	match creature_to_remove.faction:
		Creature.Faction.HUMAN:
			if living_humans_on_grid.has(creature_to_remove): living_humans_on_grid.erase(creature_to_remove)
		Creature.Faction.ALIEN:
			if living_aliens_on_grid.has(creature_to_remove): living_aliens_on_grid.erase(creature_to_remove)
		Creature.Faction.UNDEAD:
			if living_undead_on_grid.has(creature_to_remove): living_undead_on_grid.erase(creature_to_remove)
			if player_undead_roster.has(creature_to_remove): # Should not be in roster if on grid and dying
				player_undead_roster.erase(creature_to_remove) 
				emit_signal("undead_roster_changed", player_undead_roster)

	# Finally, free the creature node from the scene tree
	if is_instance_valid(creature_to_remove) and not creature_to_remove.is_queued_for_deletion():
		creature_to_remove.queue_free()

func consume_corpse(corpse_to_consume: CorpseData): # Called by ReanimateSpell
	if available_corpses.has(corpse_to_consume):
		available_corpses.erase(corpse_to_consume)
		emit_signal("corpse_removed", corpse_to_consume)
		# print_debug("Corpse of %s consumed for reanimation." % corpse_to_consume.original_creature_name)

func _remove_corpse_from_list(corpse_data: CorpseData): # Internal for decay or other reasons
	if available_corpses.has(corpse_data):
		available_corpses.erase(corpse_data)
		emit_signal("corpse_removed", corpse_data)


# --- COMBAT LOGIC ---
func _resolve_combat_in_lane(column_index: int) -> bool:
	var combat_this_lane = false
	# GDD: Sequential 1v1 engagements at the "front" of the lane.
	
	while true: # Loop until no more engagements possible in this lane for this wave
		var front_player_unit: Creature = null
		var front_alien_unit: Creature = null
		var front_player_unit_y = -1
		var front_alien_unit_y = -1

		# Find front-most player unit (Human or Undead) in this column
		# Player rows are 0 (bottom, their R1), 1 (R2), 2 (R3, closest to aliens)
		for r_idx in range(battle_grid_node.GRID_ROWS_PER_FACTION -1, -1, -1): # Check from player's R3 (idx 2) down to R1 (idx 0)
			var creature = battle_grid_node.get_creature_at(Vector2i(column_index, r_idx))
			if is_instance_valid(creature) and creature.is_alive and \
			   (creature.faction == Creature.Faction.HUMAN or creature.faction == Creature.Faction.UNDEAD):
				front_player_unit = creature
				front_player_unit_y = r_idx
				break
		
		# Find front-most Alien unit in this column
		# Alien rows are 3 (closest to player, their R3), 4 (R2), 5 (top, their R1)
		for r_idx in range(battle_grid_node.GRID_ROWS_PER_FACTION, battle_grid_node.TOTAL_GRID_ROWS): # Check from alien's R3 (idx 3) up to R1 (idx 5)
			var creature = battle_grid_node.get_creature_at(Vector2i(column_index, r_idx))
			if is_instance_valid(creature) and creature.is_alive and creature.faction == Creature.Faction.ALIEN:
				front_alien_unit = creature
				front_alien_unit_y = r_idx
				break
		
		if not is_instance_valid(front_player_unit) or not is_instance_valid(front_alien_unit):
			# One or both sides have no more units in this lane for this wave's combat sequence
			break # Exit while loop for this lane

		combat_this_lane = true
		var log_entry = "Lane %d: %s (H:%d/%d, P:%s) vs %s (H:%d/%d, P:%s)" % [
			column_index,
			front_player_unit.creature_name, front_player_unit.current_health, front_player_unit.max_health, str(front_player_unit.grid_pos),
			front_alien_unit.creature_name, front_alien_unit.current_health, front_alien_unit.max_health, str(front_alien_unit.grid_pos)
		]
		
		# Engagement Check (Unblockable Alien "Pass Through")
		var alien_passed_through = false
		if front_alien_unit.is_flying and not front_player_unit.is_flying and not front_player_unit.has_reach:
			log_entry += " - %s is Flying, %s (Ground w/o Reach) cannot block. ALIEN PASSES!" % [front_alien_unit.creature_name, front_player_unit.creature_name]
			combat_log.append(log_entry)
			_handle_alien_pass_through(front_alien_unit, "Mid-battle Unblockable")
			_remove_creature_from_game(front_alien_unit) # Alien removed after passing
			alien_passed_through = true
			# Player unit remains, alien is gone. Continue loop to see if another alien steps up.
		
		if alien_passed_through:
			continue # Re-evaluate lane with next alien if any

		# Direct Combat
		log_entry += " - ENGAGE!"
		var p_hp_before = front_player_unit.current_health
		var a_hp_before = front_alien_unit.current_health

		# Simultaneous damage
		front_player_unit.take_damage(front_alien_unit.attack_power)
		front_alien_unit.take_damage(front_player_unit.attack_power)

		log_entry += " | %s takes %d dmg (HP: %d->%d)" % [front_player_unit.creature_name, front_alien_unit.attack_power, p_hp_before, front_player_unit.current_health]
		log_entry += " | %s takes %d dmg (HP: %d->%d)" % [front_alien_unit.creature_name, front_player_unit.attack_power, a_hp_before, front_alien_unit.current_health]
		combat_log.append(log_entry)

		# Deaths are handled by the _on_creature_died signal automatically,
		# which removes them from grid and lists.
		# If both died, the loop will break on next iteration as no valid pair will be found.
		# If one died, the loop continues, and the survivor faces the next in line.
		
		# Safety break if something goes wrong to prevent infinite loop (e.g. units not dying correctly)
		if not front_player_unit.is_alive and not front_alien_unit.is_alive:
			break # Both died, next iteration will confirm no pair
		if not front_player_unit.is_alive or not front_alien_unit.is_alive:
			pass # One died, next iteration will find new opponent or end

	return combat_this_lane

func _handle_alien_pass_through(alien_creature: Creature, reason: String):
	if not is_instance_valid(alien_creature): return
	
	var damage_to_civilians = alien_creature.attack_power * 5 # Example: Alien Lvl (attack_power) * multiplier
	# print_debug("Alien %s (%s) passed through! Deals %d damage to civilian population." % [alien_creature.creature_name, reason, damage_to_civilians])
	_set_human_civilian_population(human_civilian_population - damage_to_civilians)
	
	# Alien is considered gone after passing through (for mid-battle pass)
	# For end-of-turn pass, they are also removed after dealing damage.
	# The calling function should handle removing it from lists/grid if this function doesn't.
	# For now, let this be logged, actual removal by _remove_creature_from_game.

# --- UTILITY / GETTER METHODS for other scripts ---
func get_available_corpses() -> Array[CorpseData]:
	return available_corpses # Returns a reference, be careful if modifying externally

func get_all_living_humans_and_aliens() -> Array[Creature]:
	var combined_list: Array[Creature] = []
	combined_list.append_array(living_humans_on_grid)
	combined_list.append_array(living_aliens_on_grid)
	# Filter out any invalid instances just in case, though lists should be clean
	return combined_list.filter(func(c): return is_instance_valid(c) and c.is_alive)

func get_player_undead_roster() -> Array[Creature]:
	return player_undead_roster

# --- PLAYER ACTIONS (called by UI or Input Handler) ---
func player_deploys_undead_from_roster(undead_in_roster: Creature, target_grid_pos: Vector2i) -> bool:
	if current_game_phase != GamePhase.PLAYER_PRE_BATTLE:
		# print_debug("Cannot deploy Undead outside of Pre-Battle phase.")
		return false
	if not is_instance_valid(undead_in_roster) or not player_undead_roster.has(undead_in_roster):
		# print_debug("Invalid Undead or not in roster.")
		return false
	
	# Check speed placement rules (GDD: SLOW=R1, NORMAL=R1/R2, FAST=R1/R2/R3 for player)
	var player_rows_y = [
		battle_grid_node.get_player_row_y_by_faction_row_num(1), # Player R1 (y=0)
		battle_grid_node.get_player_row_y_by_faction_row_num(2), # Player R2 (y=1)
		battle_grid_node.get_player_row_y_by_faction_row_num(3)  # Player R3 (y=2)
	]
	var allowed_rows_for_speed: Array[int] = []
	match undead_in_roster.speed_type:
		Creature.SpeedType.SLOW:
			allowed_rows_for_speed = [player_rows_y[0]]
		Creature.SpeedType.NORMAL:
			allowed_rows_for_speed = [player_rows_y[0], player_rows_y[1]]
		Creature.SpeedType.FAST:
			allowed_rows_for_speed = player_rows_y
	
	if not target_grid_pos.y in allowed_rows_for_speed:
		# print_debug("Cannot place %s (Speed: %s) at row %d. Not allowed." % [undead_in_roster.creature_name, Creature.SpeedType.keys()[undead_in_roster.speed_type], target_grid_pos.y])
		return false

	if battle_grid_node.place_creature_at(undead_in_roster, target_grid_pos):
		_add_creature_to_active_lists(undead_in_roster) # Will remove from roster, add to living_undead_on_grid
		undead_in_roster.position = battle_grid_node.get_world_position_for_grid_cell_center(target_grid_pos)
		# print_debug("Deployed %s from roster to %s" % [undead_in_roster.creature_name, str(target_grid_pos)])
		return true
	else:
		# print_debug("Failed to deploy %s to %s (cell occupied or invalid)." % [undead_in_roster.creature_name, str(target_grid_pos)])
		return false

func player_returns_undead_to_roster(undead_on_grid: Creature) -> bool:
	if current_game_phase != GamePhase.PLAYER_PRE_BATTLE:
		# print_debug("Cannot return Undead to roster outside of Pre-Battle phase.")
		return false
	if not is_instance_valid(undead_on_grid) or not living_undead_on_grid.has(undead_on_grid):
		# print_debug("Invalid Undead or not on grid.")
		return false
		
	var original_pos = undead_on_grid.grid_pos
	if battle_grid_node.remove_creature_from(original_pos) == undead_on_grid: # Ensure correct one removed
		living_undead_on_grid.erase(undead_on_grid)
		player_undead_roster.append(undead_on_grid)
		emit_signal("undead_roster_changed", player_undead_roster)
		undead_on_grid.grid_pos = Vector2i(-1,-1) # Mark as off-grid
		# print_debug("Returned %s from %s to roster." % [undead_on_grid.creature_name, str(original_pos)])
		return true
	return false

# Call this from your main Game scene or equivalent to set up critical references
func late_initialize_references(necro_node: Necromancer, bg_node: BattleGrid, units_container: Node2D):
	necromancer_node = necro_node
	battle_grid_node = bg_node
	units_container_node = units_container
	
	# Give BattleGrid a reference to this GameManager if it needs to call back (less common)
	# battle_grid_node.assign_runtime_references(self)
	
	# print_debug("GameManager late_initialize_references complete.")
