# ./scripts/GameManager.gd
extends Node
class_name GameManager

# --- SIGNALS ---
signal turn_started(turn_number: int)
signal wave_started(wave_number: int, turn_number: int)
signal player_phase_started(phase_name: String) # e.g., "PRE_BATTLE", "POST_BATTLE_REANIMATE"
signal battle_phase_started
signal wave_ended(wave_number: int, turn_number: int)
signal turn_ended(turn_number: int)
signal game_over(reason_key: String) # e.g., "humans_extinct", "player_won"
signal human_population_changed(new_population: int)
signal corpse_added(corpse: CorpseData)
signal corpse_removed(corpse: CorpseData)
signal undead_roster_changed(new_roster: Array[Creature]) # For UI to update displayed roster

# --- GAME STATE ENUMS ---
enum GamePhase { 
	NONE,                # Game is over or not started
	OUT_OF_TURN,         # Between turns, player can start next turn
	TURN_STARTING,       # Initial phase of a turn, setting up
	PLAYER_PRE_BATTLE,   # Player can place units, cast non-combat spells
	BATTLE_IN_PROGRESS,  # Combat is resolving automatically
	PLAYER_POST_BATTLE,  # Player can cast reanimation, other post-combat spells
	WAVE_ENDING,         # After post-battle, deciding to go to next wave or end turn
	TURN_ENDING          # Cleaning up turn, checking win/loss for turn
}

# --- CORE GAME VARIABLES ---
var current_turn: int = 0
var current_wave_in_turn: int = 0
var max_waves_per_turn: int = 5 # How many waves before turn must end
var waves_with_new_aliens: int = 3 # How many of those waves spawn new aliens
var human_civilian_population: int = 1000 : set = _set_human_civilian_population
const INITIAL_HUMAN_POPULATION: int = 1000
var current_game_phase: GamePhase = GamePhase.NONE

# --- ENTITY MANAGEMENT ---
var living_humans_on_grid: Array[Creature] = []
var living_aliens_on_grid: Array[Creature] = []
var living_undead_on_grid: Array[Creature] = [] # Undead currently deployed on the grid
var player_undead_roster: Array[Creature] = []  # Undead available to be deployed (not on grid)
var available_corpses: Array[CorpseData] = []   # Corpses on the grid

# --- NODE REFERENCES (Assigned by Game.gd or similar parent) ---
var necromancer_node: Necromancer
var battle_grid_node: BattleGrid
var units_container_node: Node2D # Parent node for all creature visuals

# --- CONFIGURATION ---
# Paths to creature scripts for dynamic instantiation
const CREATURE_SCRIPT_PATHS = {
	"Skeleton": "res://scripts/creatures/Skeleton.gd", "Zombie": "res://scripts/creatures/Zombie.gd",
	"Spirit": "res://scripts/creatures/Spirit.gd", "Human_Civilian": "res://scripts/creatures/Human.gd", 
	"Human_Swordsman": "res://scripts/creatures/Human.gd", "Human_Archer": "res://scripts/creatures/Human.gd",
	"Human_Knight": "res://scripts/creatures/Human.gd", "Alien_FireAnt": "res://scripts/creatures/Alien.gd",
	"Alien_Wasp": "res://scripts/creatures/Alien.gd", "Alien_Spider": "res://scripts/creatures/Alien.gd", # Example, add if used
	"Alien_Scorpion": "res://scripts/creatures/Alien.gd", # Example, add if used
	"Alien_Beetle": "res://scripts/creatures/Alien.gd",
}
const INITIAL_FINALITY_FOR_NEW_CORPSES: int = 1 # When a Human/Alien dies, their corpse gets this finality

var combat_log: Array[String] = [] # For debugging or UI display

func _ready():
	# Initialization logic that doesn't depend on external references.
	# Most setup is in start_new_game() after references are set.
	pass

# Called by Game.gd after all core nodes are ready.
func late_initialize_references(necro: Necromancer, bg: BattleGrid, units_cont: Node2D):
	necromancer_node = necro
	battle_grid_node = bg
	units_container_node = units_cont
	
	if is_instance_valid(battle_grid_node):
		battle_grid_node.assign_runtime_references(self) # BattleGrid might need GM ref for some logic
	if is_instance_valid(necromancer_node):
		necromancer_node.assign_runtime_references(self, battle_grid_node) # Necromancer needs GM and BG

# --- GAME FLOW CONTROL ---
func start_new_game():
	current_turn = 0
	_set_human_civilian_population(INITIAL_HUMAN_POPULATION) # Resets population and emits signal
	
	# Clear all existing units and corpses from grid and lists
	for child in units_container_node.get_children():
		if child is Creature: # Ensure we only queue_free creatures managed by GM
			child.queue_free()
	living_humans_on_grid.clear()
	living_aliens_on_grid.clear()
	living_undead_on_grid.clear()
	player_undead_roster.clear()
	available_corpses.clear()
	
	if is_instance_valid(battle_grid_node):
		battle_grid_node.initialize_grid_data() # Clears the logical grid
	
	# Ensure references are valid (should have been set by late_initialize_references)
	if not is_instance_valid(necromancer_node): printerr("GM: NecromancerNode missing at start_new_game!"); get_tree().quit(); return
	if not is_instance_valid(battle_grid_node): printerr("GM: BattleGridNode missing at start_new_game!"); get_tree().quit(); return
	if not is_instance_valid(units_container_node): printerr("GM: UnitsContainerNode missing at start_new_game!"); get_tree().quit(); return

	# Reset Necromancer (e.g., DE, level if game restart implies full reset)
	# necromancer_node.reset_stats() # Assuming Necromancer has a reset method
	
	_change_game_phase(GamePhase.OUT_OF_TURN)
	# print_debug("GameManager: New game started. Phase: %s" % GamePhase.keys()[current_game_phase])

func proceed_to_next_turn():
	if current_game_phase != GamePhase.OUT_OF_TURN and current_game_phase != GamePhase.TURN_ENDING and current_game_phase != GamePhase.NONE:
		# print_debug("GM: Cannot proceed to next turn. Current phase: %s" % GamePhase.keys()[current_game_phase])
		return
	
	current_turn += 1
	current_wave_in_turn = 0 # Reset wave count for the new turn
	emit_signal("turn_started", current_turn)
	_change_game_phase(GamePhase.TURN_STARTING)
	
	if is_instance_valid(necromancer_node):
		necromancer_node.replenish_de_to_max() # Replenish DE at start of turn
		
	_spawn_new_human_contingent() # Spawn initial humans for the turn
	proceed_to_next_wave() # Start the first wave

func proceed_to_next_wave():
	if current_game_phase != GamePhase.TURN_STARTING and \
	   current_game_phase != GamePhase.PLAYER_POST_BATTLE and \
	   current_game_phase != GamePhase.WAVE_ENDING:
		# print_debug("GM: Cannot proceed to next wave. Current phase: %s" % GamePhase.keys()[current_game_phase])
		return

	current_wave_in_turn += 1
	if current_wave_in_turn > max_waves_per_turn:
		_end_current_turn() # Max waves reached, end turn
		return
		
	emit_signal("wave_started", current_wave_in_turn, current_turn)
	
	if current_wave_in_turn <= waves_with_new_aliens:
		_spawn_new_alien_wave() # Spawn aliens for this wave
		
	_change_game_phase(GamePhase.PLAYER_PRE_BATTLE)
	emit_signal("player_phase_started", "PRE_BATTLE")

func player_ends_pre_battle_phase():
	if current_game_phase != GamePhase.PLAYER_PRE_BATTLE: return
	_initiate_battle_phase()

func _initiate_battle_phase():
	_change_game_phase(GamePhase.BATTLE_IN_PROGRESS)
	emit_signal("battle_phase_started")
	combat_log.clear() # Clear log for new battle
	
	# Resolve combat lane by lane
	for col_idx in range(battle_grid_node.GRID_COLUMNS):
		_resolve_combat_in_lane(col_idx)
		
	# After all lanes resolved for this "round" of combat (if simultaneous)
	# Or if turn-based, this would be more complex. Assuming simultaneous resolution per lane.
	_change_game_phase(GamePhase.PLAYER_POST_BATTLE)
	emit_signal("player_phase_started", "POST_BATTLE_REANIMATE")

func player_ends_post_battle_phase():
	if current_game_phase != GamePhase.PLAYER_POST_BATTLE: return
	_end_current_wave()

func _end_current_wave():
	emit_signal("wave_ended", current_wave_in_turn, current_turn)
	_change_game_phase(GamePhase.WAVE_ENDING)
	
	# Check if all aliens that were supposed to spawn this turn have spawned and are defeated
	var aliens_remain_on_grid = living_aliens_on_grid.size() > 0
	var more_aliens_expected_this_turn = current_wave_in_turn < waves_with_new_aliens
	
	if not aliens_remain_on_grid and not more_aliens_expected_this_turn:
		# All spawned aliens defeated, and no more new alien waves this turn
		_end_current_turn()
	# Else, the player can choose to proceed to the next wave (via UI button connected to proceed_to_next_wave)
	# or if max_waves_per_turn is reached, proceed_to_next_wave will call _end_current_turn.

func _end_current_turn():
	_change_game_phase(GamePhase.TURN_ENDING)
	
	# Handle aliens that passed all defenses
	var passed_aliens_this_turn: Array[Creature] = []
	for alien_unit in living_aliens_on_grid.duplicate(): # Iterate all living aliens
		if not is_instance_valid(alien_unit) or not alien_unit.is_alive:
			continue
		# Player's "home row" from their perspective is Row 1.
		var player_home_row_y = battle_grid_node.get_player_row_y_by_faction_row_num(1) # Should be y=5
		if alien_unit.grid_pos.y == player_home_row_y:
			passed_aliens_this_turn.append(alien_unit)
			
	for alien_passed in passed_aliens_this_turn:
		_handle_alien_pass_through(alien_passed, "EndTurnPass")
		if is_instance_valid(alien_passed): # Re-check, might have been removed by pass_through logic
			_remove_creature_from_game(alien_passed) # Remove from grid and lists

	# Clear all corpses at the end of the turn
	for corpse_to_remove in available_corpses.duplicate(): # Iterate over a copy
		_remove_corpse_from_list(corpse_to_remove) # Emits signal
	available_corpses.clear() # Ensure list is empty
	
	emit_signal("turn_ended", current_turn)
	
	# Check win/loss conditions for the game
	if current_turn >= 20 and human_civilian_population > 0: # Example win condition: Survive 20 turns
		_set_game_over("player_won", "Survived all turns!")
		return
	if human_civilian_population <= 0: # Loss condition handled by _set_human_civilian_population
		# _set_game_over already called
		return
		
	_change_game_phase(GamePhase.OUT_OF_TURN) # Ready for player to start next turn

func _set_human_civilian_population(value: int):
	var old_pop = human_civilian_population
	human_civilian_population = max(0, value) # Population cannot be negative
	if old_pop != human_civilian_population:
		emit_signal("human_population_changed", human_civilian_population)
		if human_civilian_population == 0 and current_game_phase != GamePhase.NONE: # Check if not already game over
			_set_game_over("humans_extinct", "Human population reached zero.")

func _change_game_phase(new_phase: GamePhase):
	if current_game_phase != new_phase:
		current_game_phase = new_phase
		# print_debug("GameManager: Phase changed to %s" % GamePhase.keys()[current_game_phase])

func _set_game_over(reason_key: String, _message: String): # _message for potential future use
	if current_game_phase == GamePhase.NONE and reason_key != "": return # Already game over
	_change_game_phase(GamePhase.NONE) # Set phase to NONE to stop game logic
	emit_signal("game_over", reason_key) # UI listens to this
	# print_debug("GameManager: GAME OVER. Reason: %s" % reason_key)


# --- UNIT SPAWNING AND MANAGEMENT ---
func _spawn_new_human_contingent():
	# Humans spawn in player rows (now bottom: y=3,4,5, from their perspective Row 3,2,1)
	var humans_to_spawn: Array[Dictionary] = [
		{"type": "Human_Swordsman", "config": {"creature_name": "Swordsman", "max_health": 15, "attack_power": 4, "speed_type": Creature.SpeedType.NORMAL, "sprite_texture_path": "res://assets/images/placerholder_swordsman.png"}},
		{"type": "Human_Archer", "config": {"creature_name": "Archer", "max_health": 10, "attack_power": 3, "speed_type": Creature.SpeedType.NORMAL, "has_reach": true, "sprite_texture_path": "res://assets/images/placerholder_archer.png"}},
		{"type": "Human_Civilian", "config": {"creature_name": "Civilian", "max_health": 5, "attack_power": 0, "speed_type": Creature.SpeedType.SLOW, "sprite_texture_path": "res://assets/images/placerholder_civilian.png"}},
	]
	_auto_place_units(humans_to_spawn, Creature.Faction.HUMAN)

func _spawn_new_alien_wave():
	# Aliens spawn in alien rows (now top: y=0,1,2, from their perspective Row 3,2,1)
	var aliens_to_spawn: Array[Dictionary] = [
		{"type": "Alien_FireAnt", "config": {"creature_name": "FireAnt", "max_health": 8, "attack_power": 3, "speed_type": Creature.SpeedType.FAST, "sprite_texture_path": "res://assets/images/placeholder_fireant.png"}},
		{"type": "Alien_Wasp", "config": {"creature_name": "Wasp", "max_health": 6, "attack_power": 2, "speed_type": Creature.SpeedType.FAST, "is_flying": true, "sprite_texture_path": "res://assets/images/placeholder_wasp.png"}},
	]
	if current_wave_in_turn == 2: # Example: wave-specific spawns
		aliens_to_spawn.append({"type": "Alien_Beetle", "config": {"creature_name": "Beetle", "max_health": 20, "attack_power": 2, "speed_type": Creature.SpeedType.SLOW, "sprite_texture_path": "res://assets/images/placeholder_beetle.png"}})
	_auto_place_units(aliens_to_spawn, Creature.Faction.ALIEN)

func _auto_place_units(units_to_spawn_data: Array[Dictionary], faction: Creature.Faction):
	if not is_instance_valid(battle_grid_node):
		printerr("GM: BattleGridNode not valid in _auto_place_units.")
		return
		
	var faction_rows_y_coords: Array[int] = [] # Actual grid y-coordinates to try spawning in

	if faction == Creature.Faction.HUMAN or faction == Creature.Faction.UNDEAD: # Player controlled units
		# Player units spawn in their designated rows (their "Row 1, 2, 3" = grid y=5,4,3 respectively)
		# Order of preference for spawning: their Row 1 (closest to their edge), then Row 2, then Row 3.
		faction_rows_y_coords = [
			battle_grid_node.get_player_row_y_by_faction_row_num(1), # y=5 (Back)
			battle_grid_node.get_player_row_y_by_faction_row_num(2), # y=4 (Mid)
			battle_grid_node.get_player_row_y_by_faction_row_num(3)  # y=3 (Front)
		]
	elif faction == Creature.Faction.ALIEN:
		# Alien units spawn in their designated rows (their "Row 1, 2, 3" = grid y=0,1,2 respectively)
		# Order of preference for spawning: their Row 1 (closest to their edge), then Row 2, then Row 3.
		faction_rows_y_coords = [
			battle_grid_node.get_alien_row_y_by_faction_row_num(1), # y=0 (Back for aliens - top of screen)
			battle_grid_node.get_alien_row_y_by_faction_row_num(2), # y=1 (Mid for aliens)
			battle_grid_node.get_alien_row_y_by_faction_row_num(3)  # y=2 (Front for aliens)
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
		for row_y in faction_rows_y_coords: # Iterate through preferred rows
			if row_y == -1: continue # Skip if get_..._row_num returned an error (e.g. invalid faction row num)

			# Try to find an empty cell in this row, from left to right (col 0 to N)
			var target_pos = battle_grid_node.find_first_empty_cell_in_row(row_y)
			if target_pos != Vector2i(-1,-1): # Found an empty cell
				if battle_grid_node.place_creature_at(creature_node, target_pos):
					_add_creature_to_active_lists(creature_node)
					# print_debug("GM: Auto-placed %s (%s) at %s" % [creature_node.creature_name, Creature.Faction.keys()[faction], str(target_pos)])
					placed = true
					break # Placed this unit, move to next unit_data in units_to_spawn_data
		
		if not placed:
			# print_debug("GM: Could not find empty cell to auto-place %s (%s)." % [unit_data["config"].get("creature_name", unit_data["type"]), Creature.Faction.keys()[faction]])
			creature_node.queue_free() # Clean up unplaced creature to prevent memory leaks

func _prepare_creature_node_base() -> Node2D:
	# Creates the basic Node2D structure for a creature (Node2D root with a Sprite2D child).
	# The specific creature script (Human, Alien, Skeleton, etc.) will be attached to this Node2D.
	var creature_base_node = Node2D.new()
	var sprite_node = Sprite2D.new()
	sprite_node.name = "Sprite" # Creature.gd expects a child named "Sprite"
	creature_base_node.add_child(sprite_node)
	return creature_base_node

func spawn_reanimated_creature(config_from_spell: Dictionary) -> Creature:
	var script_path = config_from_spell.get("creature_class_script_path", "")
	if script_path == "": printerr("GM: No script_path provided for reanimation."); return null
	
	var creature_node_base = _prepare_creature_node_base()
	var script_resource = load(script_path)
	if not script_resource:
		printerr("GM: Failed to load script resource at %s" % script_path)
		creature_node_base.queue_free()
		return null
	
	creature_node_base.set_script(script_resource)
	var actual_creature: Creature = creature_node_base as Creature # Cast to Creature type
	
	if not is_instance_valid(actual_creature):
		printerr("GM: Node did not correctly become a Creature after script set: %s" % script_path)
		creature_node_base.queue_free()
		return null
		
	# Assign essential references before initialization
	actual_creature.game_manager = self
	actual_creature.battle_grid = battle_grid_node
	
	var final_config = config_from_spell.duplicate(true) # Work with a copy
	# Ensure faction is UNDEAD for reanimated creatures, overriding anything from spell config
	final_config["faction"] = Creature.Faction.UNDEAD
	
	# Set default sprite if not provided by the spell config (already handled in your version)
	var undead_type_name = config_from_spell.get("creature_name", "Undead").to_lower()
	if not final_config.has("sprite_texture_path"):
		if undead_type_name.contains("skeleton"): final_config["sprite_texture_path"] = "res://assets/images/placeholder_skeleton.png"
		elif undead_type_name.contains("zombie"): final_config["sprite_texture_path"] = "res://assets/images/placeholder_zombie.png"
		elif undead_type_name.contains("spirit"): final_config["sprite_texture_path"] = "res://assets/images/placeholder_spirit.png"
		else: final_config["sprite_texture_path"] = "res://assets/images/placeholder_undead.png" # Generic undead placeholder
		
	actual_creature.initialize_creature(final_config) # Initialize with all data
	units_container_node.add_child(actual_creature) # Add to scene tree under UnitsContainer
	
	# Add to player's undead roster (available for deployment)
	if not player_undead_roster.has(actual_creature):
		player_undead_roster.append(actual_creature)
	emit_signal("undead_roster_changed", player_undead_roster)
	
	# Connect death signal
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
		creature_node_base.queue_free()
		return null
		
	creature_node_base.set_script(script_resource)
	var actual_creature: Creature = creature_node_base as Creature
	
	if not is_instance_valid(actual_creature):
		printerr("GM: Node did not correctly become a Creature for type_key: %s" % type_key)
		creature_node_base.queue_free()
		return null
		
	actual_creature.game_manager = self
	actual_creature.battle_grid = battle_grid_node
	
	var final_cfg = config.duplicate(true)
	final_cfg["faction"] = faction_override # Ensure correct faction is set
	
	# Ensure a sprite texture path exists, defaulting if necessary
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
			# If it was in roster and now deployed, remove from roster
			if player_undead_roster.has(creature):
				player_undead_roster.erase(creature)
				emit_signal("undead_roster_changed", player_undead_roster)

func _on_creature_died(creature_died: Creature):
	if not is_instance_valid(creature_died): return
	
	# Create CorpseData based on the creature that died
	var corpse_payload = creature_died.get_data_for_corpse_creation() # Creature.gd provides this
	corpse_payload["grid_pos_on_death"] = creature_died.grid_pos # Record where it died
	corpse_payload["turn_of_death"] = current_turn
	
	# Assign initial finality based on faction
	if creature_died.faction == Creature.Faction.HUMAN or creature_died.faction == Creature.Faction.ALIEN:
		corpse_payload["finality_counter"] = INITIAL_FINALITY_FOR_NEW_CORPSES
	else: # Undead creature died, use its finality_counter from the payload
		corpse_payload["finality_counter"] = corpse_payload.get("current_finality_counter_on_death", 0)
		
	var new_corpse = CorpseData.new(corpse_payload)
	available_corpses.append(new_corpse)
	emit_signal("corpse_added", new_corpse)
	
	# Remove the creature from game logic and scene
	_remove_creature_from_game(creature_died)

func _remove_creature_from_game(creature_to_remove: Creature):
	if not is_instance_valid(creature_to_remove): return
	
	# Remove from BattleGrid logic
	if battle_grid_node.is_valid_grid_position(creature_to_remove.grid_pos):
		battle_grid_node.remove_creature_from(creature_to_remove.grid_pos)
		
	# Remove from active lists
	match creature_to_remove.faction:
		Creature.Faction.HUMAN: living_humans_on_grid.erase(creature_to_remove)
		Creature.Faction.ALIEN: living_aliens_on_grid.erase(creature_to_remove)
		Creature.Faction.UNDEAD:
			living_undead_on_grid.erase(creature_to_remove)
			# If an Undead dies and was somehow still in roster (should not happen if deployed correctly), remove it.
			if player_undead_roster.has(creature_to_remove): 
				player_undead_roster.erase(creature_to_remove)
				emit_signal("undead_roster_changed", player_undead_roster)
				
	# Remove from scene tree if not already queued for deletion
	if not creature_to_remove.is_queued_for_deletion():
		creature_to_remove.queue_free()

func consume_corpse(corpse: CorpseData):
	if available_corpses.has(corpse):
		available_corpses.erase(corpse)
		emit_signal("corpse_removed", corpse)
		# The CorpseData resource itself doesn't need queue_free unless it's a node.
		# If it's just a Resource, removing from array is enough for GC if no other refs.

func _remove_corpse_from_list(corpse: CorpseData): # Internal helper
	if available_corpses.has(corpse):
		available_corpses.erase(corpse)
		emit_signal("corpse_removed", corpse)

# --- COMBAT RESOLUTION ---
func _resolve_combat_in_lane(col_idx: int) -> bool:
	var combat_occurred_this_lane = false
	while true: # Loop to handle multiple combats if units die and others step up
		var player_unit: Creature = null
		var alien_unit: Creature = null

		# Find foremost player unit (Human or Undead) in this column.
		# Player units are in rows y=3,4,5 (their front to back). Search front first.
		var player_rows_to_search = [
			battle_grid_node.get_player_row_y_by_faction_row_num(3), # y=3 (Player Front)
			battle_grid_node.get_player_row_y_by_faction_row_num(2), # y=4 (Player Mid)
			battle_grid_node.get_player_row_y_by_faction_row_num(1)  # y=5 (Player Back)
		]
		for r_y in player_rows_to_search:
			if r_y == -1: continue # Invalid row coordinate
			var c = battle_grid_node.get_creature_at(Vector2i(col_idx, r_y))
			if is_instance_valid(c) and c.is_alive and (c.faction == Creature.Faction.HUMAN or c.faction == Creature.Faction.UNDEAD):
				player_unit = c
				break # Found the foremost player unit

		# Find foremost alien unit in this column.
		# Alien units are in rows y=2,1,0 (their front to back). Search front first.
		var alien_rows_to_search = [
			battle_grid_node.get_alien_row_y_by_faction_row_num(3), # y=2 (Alien Front)
			battle_grid_node.get_alien_row_y_by_faction_row_num(2), # y=1 (Alien Mid)
			battle_grid_node.get_alien_row_y_by_faction_row_num(1)  # y=0 (Alien Back)
		]
		for r_y in alien_rows_to_search:
			if r_y == -1: continue
			var c = battle_grid_node.get_creature_at(Vector2i(col_idx, r_y))
			if is_instance_valid(c) and c.is_alive and c.faction == Creature.Faction.ALIEN:
				alien_unit = c
				break # Found the foremost alien unit

		# If no pair to fight (one or both sides have no units in this column), break loop for this column.
		if not is_instance_valid(player_unit) or not is_instance_valid(alien_unit):
			break 

		# Units are considered engaged if they are the foremost units of opposing factions in the same column.
		# Specific row check for direct adjacency (e.g. player at y=3, alien at y=2) is implicit if they are foremost.
		combat_occurred_this_lane = true
		var log_entry = "L%d: %s (P@%s) vs %s (A@%s)" % [col_idx, player_unit.creature_name, str(player_unit.grid_pos.y), alien_unit.creature_name, str(alien_unit.grid_pos.y)]

		var alien_flew_over_this_combat = false
		if alien_unit.is_flying and not player_unit.is_flying and not player_unit.has_reach:
			log_entry += " - ALIEN FLIES OVER PLAYER UNIT!"
			# Alien passes this specific player unit. It might still encounter other player units
			# further back in the column in subsequent iterations if this player_unit dies.
			# For now, assume flying over means it bypasses THIS combat exchange.
			# It will damage population and be removed from grid.
			_handle_alien_pass_through(alien_unit, "MidBattleFlyOver")
			_remove_creature_from_game(alien_unit) # Alien is gone from this combat
			alien_flew_over_this_combat = true
			# No damage exchange in this specific interaction. Loop to find next alien if any.
		
		if alien_flew_over_this_combat:
			combat_log.append(log_entry)
			continue # Re-evaluate combat in the lane (player unit vs potentially new alien)

		# Standard combat damage exchange
		var p_hp_old = player_unit.current_health
		var a_hp_old = alien_unit.current_health

		player_unit.take_damage(alien_unit.attack_power) # Player unit takes damage
		alien_unit.take_damage(player_unit.attack_power) # Alien unit takes damage

		log_entry += " | P.HP: %d->%d, A.HP: %d->%d" % [p_hp_old, player_unit.current_health, a_hp_old, alien_unit.current_health]
		combat_log.append(log_entry)

		# If one or both died, they will be removed by their `die()` signal -> `_on_creature_died`.
		# The loop will then re-evaluate with new front-liners, if any.
		# If both are still alive after exchanging blows, they remain for the next game tick/event.
		# This loop is primarily for handling units dying and new ones stepping up *within the same combat phase resolution*.
		# If no one dies, this iteration of combat for this lane is over.
		if (is_instance_valid(player_unit) and not player_unit.is_alive) or \
		   (is_instance_valid(alien_unit) and not alien_unit.is_alive):
			# Death(s) occurred, loop will re-evaluate for new front-liners.
			pass 
		else:
			# Both survived this exchange, no new units step up immediately.
			break # End combat for this lane in this resolution pass.
			
	return combat_occurred_this_lane

func _handle_alien_pass_through(alien: Creature, reason: String):
	if not is_instance_valid(alien): return
	# print_debug("Alien '%s' (AP:%d) passed through. Reason: %s. Damaging population." % [alien.creature_name, alien.attack_power, reason])
	var damage_to_population = alien.attack_power * 5 # Example formula
	_set_human_civilian_population(human_civilian_population - damage_to_population)

# --- UTILITY / GETTER METHODS ---
func get_available_corpses() -> Array[CorpseData]:
	# Filter out any potentially invalid instances if CorpseData could become invalid (unlikely for Resources)
	return available_corpses.filter(func(c): return is_instance_valid(c) and c is CorpseData)

func get_all_living_humans_and_aliens() -> Array[Creature]:
	var all_living_non_undead: Array[Creature] = []
	all_living_non_undead.append_array(living_humans_on_grid.filter(func(c): return is_instance_valid(c) and c.is_alive))
	all_living_non_undead.append_array(living_aliens_on_grid.filter(func(c): return is_instance_valid(c) and c.is_alive))
	return all_living_non_undead

func get_player_undead_roster() -> Array[Creature]:
	return player_undead_roster.filter(func(c): return is_instance_valid(c)) # Ensure valid instances

# --- PLAYER ACTIONS (Called by Game.gd via Necromancer or UI) ---
func player_deploys_undead_from_roster(undead: Creature, grid_pos: Vector2i) -> bool:
	if current_game_phase != GamePhase.PLAYER_PRE_BATTLE and current_game_phase != GamePhase.PLAYER_POST_BATTLE :
		# print_debug("GM: Cannot deploy Undead. Not in valid phase. Phase: %s" % GamePhase.keys()[current_game_phase])
		return false
	if not is_instance_valid(undead) or not player_undead_roster.has(undead):
		# print_debug("GM: Cannot deploy Undead. Invalid instance or not in roster.")
		return false

	# Undead are player units, deploy to player rows (bottom half: y=3,4,5 for Faction Rows 3,2,1)
	# Player Row 1 (their back, y=5), Player Row 2 (mid, y=4), Player Row 3 (front, y=3).
	var p_row1_y = battle_grid_node.get_player_row_y_by_faction_row_num(1) # y=5 (Back)
	var p_row2_y = battle_grid_node.get_player_row_y_by_faction_row_num(2) # y=4 (Mid)
	var p_row3_y = battle_grid_node.get_player_row_y_by_faction_row_num(3) # y=3 (Front)

	var allowed_rows_y_coords: Array[int] = []
	match undead.speed_type:
		Creature.SpeedType.SLOW:
			allowed_rows_y_coords = [p_row1_y] # Only back row (y=5)
		Creature.SpeedType.NORMAL:
			allowed_rows_y_coords = [p_row1_y, p_row2_y] # Back or mid row (y=5, y=4)
		Creature.SpeedType.FAST:
			allowed_rows_y_coords = [p_row1_y, p_row2_y, p_row3_y] # Any player row (y=5, y=4, y=3)
	
	allowed_rows_y_coords = allowed_rows_y_coords.filter(func(y): return y != -1) # Remove invalid coords

	if not allowed_rows_y_coords.has(grid_pos.y) or not battle_grid_node.get_player_rows_indices().has(grid_pos.y) :
		# print_debug("GM: Deploy Undead %s (Speed:%s) to %s failed. Not an allowed player row for speed or general placement." % [undead.creature_name, Creature.SpeedType.keys()[undead.speed_type], str(grid_pos)])
		return false

	if battle_grid_node.place_creature_at(undead, grid_pos):
		_add_creature_to_active_lists(undead) # This will remove from roster and add to living_undead_on_grid
		# print_debug("GM: Deployed Undead %s to %s." % [undead.creature_name, str(grid_pos)])
		return true
	else:
		# print_debug("GM: Failed to place Undead %s at %s (cell likely occupied or invalid)." % [undead.creature_name, str(grid_pos)])
		return false

func player_returns_undead_to_roster(undead: Creature) -> bool:
	if current_game_phase != GamePhase.PLAYER_PRE_BATTLE and current_game_phase != GamePhase.PLAYER_POST_BATTLE:
		# print_debug("GM: Cannot return Undead to roster. Not in valid phase.")
		return false
	if not is_instance_valid(undead) or not living_undead_on_grid.has(undead):
		# print_debug("GM: Cannot return Undead. Invalid instance or not on grid.")
		return false

	var old_pos = undead.grid_pos
	var removed_creature_ref = battle_grid_node.remove_creature_from(old_pos) # Get what was actually removed

	if removed_creature_ref == undead: # Successfully removed the correct Undead from grid
		living_undead_on_grid.erase(undead)
		if not player_undead_roster.has(undead): # Avoid duplicates if somehow already there
			player_undead_roster.append(undead)
		emit_signal("undead_roster_changed", player_undead_roster)
		undead.grid_pos = Vector2i(-1,-1) # Invalidate grid position (Creature's setter handles visual update if needed)
		# print_debug("GM: Returned Undead %s from %s to roster." % [undead.creature_name, str(old_pos)])
		return true
	else:
		# print_debug("GM: Failed to remove Undead %s from grid at %s (cell empty or different creature: %s)." % [undead.creature_name, str(old_pos), str(removed_creature_ref)])
		# If it was already removed or not there, but still in living_undead_on_grid, clean up list.
		if living_undead_on_grid.has(undead): living_undead_on_grid.erase(undead) # Defensive
		if not player_undead_roster.has(undead): player_undead_roster.append(undead) # Ensure it's back
		emit_signal("undead_roster_changed", player_undead_roster) # Emit roster change anyway
		return false
