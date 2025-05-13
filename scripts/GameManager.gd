# GameManager.gd
class_name GameManager
extends Node

signal wave_started(wave_number)
signal wave_ended(wave_number)
signal turn_started(turn_number)
signal turn_ended(turn_number)
signal human_population_changed(new_count)
signal creature_died(creature_instance, last_position, creature_original_data) # Added original data for reanimation
signal request_reanimate(dead_creature_info) # Passes data of the dead creature

# Grid layout
const GRID_COLUMNS = 8
const TOTAL_GRID_ROWS = 6
const ATTACKER_ROWS_COUNT = 3
const DEFENDER_ROWS_COUNT = 3

# Screen row indices for attackers (top part of the grid)
const ATTACKER_SCREEN_ROW_START = 0
const ATTACKER_FIRST_SCREEN_ROW = 0      # Their "first row" (closest to top of screen)
const ATTACKER_SECOND_SCREEN_ROW = 1
const ATTACKER_THIRD_SCREEN_ROW = 2       # Their "third row" (closest to middle)

# Screen row indices for defenders (bottom part of the grid)
const DEFENDER_SCREEN_ROW_START = 3
const DEFENDER_THIRD_SCREEN_ROW = 3       # Their "third row" (closest to middle)
const DEFENDER_SECOND_SCREEN_ROW = 4
const DEFENDER_FIRST_SCREEN_ROW = 5      # Their "first row" (closest to bottom of screen)


var human_population: int = 1000
var current_wave_number: int = 0
var is_wave_active: bool = false
var wave_timer: Timer = null

var current_turn: int = 0
var waves_per_turn: int = 3 # Example
var current_wave_in_turn: int = 0

var living_humans: Array[Human] = []
var living_aliens: Array[Alien] = []
var living_undead: Array[Undead] = []

# Stores data of creatures that died and can be reanimated
# Each entry: { "original_creature": Creature, "position": Vector2, "time_of_death": int, "original_class_name": String }
var dead_creatures_for_reanimation = []

@onready var battle_grid: Node2D = $"../BattleGrid"
@onready var necromancer: Node2D = $"../Necromancer"


func _ready() -> void:
	print("GameManager ready. Arisen awaits.")
	wave_timer = Timer.new()
	wave_timer.one_shot = true
	wave_timer.wait_time = 5.0 # Time between waves
	wave_timer.connect("timeout", _on_wave_timer_timeout)
	add_child(wave_timer) # Important: Timer needs to be in the scene tree

	if necromancer:
		connect("turn_started", Callable(necromancer, "_on_turn_started")) # Ensure Necromancer has this
		connect("request_reanimate", Callable(necromancer, "handle_reanimation_request")) # Ensure Necromancer has this

func start_game() -> void:
	print("The invasion begins!")
	current_turn = 0
	current_wave_in_turn = 0
	current_wave_number = 0
	human_population = 100 # Starting population
	emit_signal("human_population_changed", human_population)
	# Clear any existing creatures
	for creature_array in [living_humans, living_aliens, living_undead]:
		for creature_instance in creature_array:
			if is_instance_valid(creature_instance):
				creature_instance.queue_free()
		creature_array.clear()
	dead_creatures_for_reanimation.clear()
	battle_grid.initialize_grid() # Reset grid state

	start_next_turn()

func start_next_turn() -> void:
	current_turn += 1
	current_wave_in_turn = 0
	emit_signal("turn_started", current_turn)
	# Initial human spawn at start of game/turn if desired
	if current_turn == 1: # Example: Spawn initial humans only at the very start
		spawn_initial_humans(5) # Spawn 5 humans
	start_next_wave()

func start_next_wave() -> void:
	current_wave_number += 1
	current_wave_in_turn += 1
	is_wave_active = true
	emit_signal("wave_started", current_wave_number)
	spawn_wave_aliens(5 + current_wave_number) # Example: Number of aliens increases

func _on_wave_timer_timeout() -> void:
	if current_wave_in_turn >= waves_per_turn:
		emit_signal("turn_ended", current_turn)
		# Potentially add a "preparation phase" call here for the player
		start_next_turn()
	else:
		start_next_wave()

func end_wave_procedures() -> void:
	is_wave_active = false
	emit_signal("wave_ended", current_wave_number)
	
	# Simplified: Process combat, then check for next phase
	# Movement is now part of placement. If turn-based movement is needed, add here.
	process_combat()

	if living_aliens.is_empty() and human_population > 0 : # Wave cleared
		print("Wave %d cleared!" % current_wave_number)
		wave_timer.start() # Start timer for next wave/turn
	elif human_population <= 0:
		game_over(false) # Humans lost
	# Add other win/loss conditions for the wave/turn if necessary

func check_game_state_after_combat() -> void:
	if human_population <= 0:
		game_over(false)
		return
	if living_aliens.is_empty() and is_wave_active: # All aliens defeated this wave
		end_wave_procedures()

# New Placement Logic Core
# Returns: Dictionary { "position": Vector2, "shifts": Array[Dictionary] }
# OR null if no spot found.
# Note the change in return type from '-> Dictionary' to '-> Variant'
func _find_placement_position_and_shifts(creature_to_place: Creature) -> Variant: # MODIFIED LINE
	var is_attacker = creature_to_place is Alien
	var speed = creature_to_place.speed_type

	var target_lanes = [] # Columns 0 to GRID_COLUMNS - 1
	for i in range(GRID_COLUMNS): target_lanes.append(i)

	var preferred_rows_orders = [] # Array of screen row indices

	if is_attacker:
		match speed:
			Creature.SpeedType.SLOW:
				preferred_rows_orders = [[ATTACKER_FIRST_SCREEN_ROW, ATTACKER_SECOND_SCREEN_ROW, ATTACKER_THIRD_SCREEN_ROW]] # Push
			Creature.SpeedType.FAST:
				preferred_rows_orders = [[ATTACKER_THIRD_SCREEN_ROW], [ATTACKER_SECOND_SCREEN_ROW], [ATTACKER_FIRST_SCREEN_ROW]] # No push
			_:
				preferred_rows_orders = [[ATTACKER_FIRST_SCREEN_ROW], [ATTACKER_SECOND_SCREEN_ROW], [ATTACKER_THIRD_SCREEN_ROW]] # No push
	else: # Defender
		match speed:
			Creature.SpeedType.SLOW:
				preferred_rows_orders = [[DEFENDER_FIRST_SCREEN_ROW, DEFENDER_SECOND_SCREEN_ROW, DEFENDER_THIRD_SCREEN_ROW]] # Push
			Creature.SpeedType.FAST:
				preferred_rows_orders = [[DEFENDER_THIRD_SCREEN_ROW], [DEFENDER_SECOND_SCREEN_ROW], [DEFENDER_FIRST_SCREEN_ROW]] # No push
			_:
				preferred_rows_orders = [[DEFENDER_FIRST_SCREEN_ROW], [DEFENDER_SECOND_SCREEN_ROW], [DEFENDER_THIRD_SCREEN_ROW]] # No push
	
	for lane_idx in target_lanes:
		for row_order_attempt in preferred_rows_orders:
			var shifts = [] # Shifts for this specific attempt (lane + row_order)
			var placement_coord = Vector2.ONE * -1

			if speed == Creature.SpeedType.SLOW: # Handle pushing logic
				var r1_coord = Vector2(lane_idx, row_order_attempt[0])
				var r2_coord = Vector2(lane_idx, row_order_attempt[1])
				var r3_coord = Vector2(lane_idx, row_order_attempt[2])

				var c1 = battle_grid.get_creature_at_coords(r1_coord)
				var c2 = battle_grid.get_creature_at_coords(r2_coord)
				var c3 = battle_grid.get_creature_at_coords(r3_coord) # Creature in the 3rd cell of the push path

				if c1 == null: # First row in order is empty
					placement_coord = r1_coord
				elif c2 == null: # Second row is empty, c1 can move
					shifts.append({"creature": c1, "from": r1_coord, "to": r2_coord})
					placement_coord = r1_coord
				elif c3 == null: # Third row is empty, c1 and c2 can move
					# Only add c2 to shifts if it actually exists
					if c2 != null: # This check was missing, c2 could be null if r2_coord was empty
						shifts.append({"creature": c2, "from": r2_coord, "to": r3_coord})
					# c1 always exists if we are in this part of the elif
					shifts.append({"creature": c1, "from": r1_coord, "to": r2_coord})
					placement_coord = r1_coord
				# Else: cannot push, column is full for slow unit in this lane
			
			else: # Fast or Normal - no pushing, just find first empty preferred
				for screen_row_idx in row_order_attempt:
					var current_coord = Vector2(lane_idx, screen_row_idx)
					if battle_grid.is_cell_empty(current_coord):
						placement_coord = current_coord
						break # Found a spot in this lane
			
			if placement_coord != Vector2.ONE * -1:
				return {"position": placement_coord, "shifts": shifts} # This is a Dictionary
				
	return null # No position found - This is now allowed due to '-> Variant'

func _execute_placement(creature_to_place: Creature, placement_info: Dictionary) -> bool:
	if placement_info == null:
		print_debug("Placement failed for ", creature_to_place.get_class(), ": No suitable spot.")
		creature_to_place.queue_free() # Clean up if not placed
		return false

	# Execute shifts
	for shift_op in placement_info.shifts:
		var shifted_creature: Creature = shift_op.creature
		battle_grid.remove_creature_from_coords(shift_op.from)
		# shifted_creature.play_move_animation(shift_op.to) # Optional animation call
		battle_grid.place_creature_at_coords(shifted_creature, shift_op.to)
		print_debug("Shifted ", shifted_creature.get_class(), " from ", shift_op.from, " to ", shift_op.to)

	# Place the new creature
	battle_grid.place_creature_at_coords(creature_to_place, placement_info.position)
	print_debug("Placed new ", creature_to_place.get_class(), " at ", placement_info.position)
	
	# Add to respective living list - AFTER it's successfully placed
	if creature_to_place is Alien:
		living_aliens.append(creature_to_place)
	elif creature_to_place is Human:
		living_humans.append(creature_to_place)
	elif creature_to_place is Undead:
		living_undead.append(creature_to_place)
	
	add_child(creature_to_place) # Ensure it's in the scene tree for processing
	return true

func spawn_creature_with_logic(creature: Creature) -> bool:
	var placement_info = _find_placement_position_and_shifts(creature)
	if placement_info:
		return _execute_placement(creature, placement_info)
	else:
		print("Could not find placement for new creature: ", creature.name)
		if is_instance_valid(creature) and creature.get_parent() == null: # If not added to scene yet
			creature.queue_free()
		return false

func spawn_wave_aliens(count: int) -> void:
	for _i in range(count):
		var type_roll = randi() % 5
		var new_alien: Alien
		match type_roll:
			0: new_alien = Alien.create_fireant()
			1: new_alien = Alien.create_wasp()
			2: new_alien = Alien.create_spider()
			3: new_alien = Alien.create_scorpion()
			_: new_alien = Alien.create_beetle()
		new_alien.name = new_alien.get_class() + str(living_aliens.size() + 1) # Unique name
		spawn_creature_with_logic(new_alien)
	check_game_state_after_combat() # Check if wave is instantly over (e.g. no valid spots)

func spawn_initial_humans(count: int) -> void:
	for _i in range(count):
		var type_roll = randi() % 5
		var new_human: Human
		match type_roll:
			0: new_human = Human.create_civilian()
			1: new_human = Human.create_spearman()
			2: new_human = Human.create_swordsman()
			3: new_human = Human.create_archer()
			_: new_human = Human.create_knight()
		new_human.name = new_human.get_class() + str(living_humans.size() + 1)
		spawn_creature_with_logic(new_human)

func process_combat() -> void:
	var all_combatants = living_aliens + living_humans + living_undead
	all_combatants.sort_custom(func(a,b): return a.lane < b.lane if a.lane != b.lane else a.row < b.row) # Process systematically

	var combat_actions = [] # Store {attacker, target, damage}

	# Determine targets
	for creature_a in all_combatants:
		if creature_a.is_dead(): continue

		for creature_b in all_combatants:
			if creature_a == creature_b or creature_b.is_dead(): continue

			# Basic targeting: different factions, in same lane or adjacent based on reach
			var is_a_attacker_faction = creature_a is Alien
			var is_b_attacker_faction = creature_b is Alien
			if is_a_attacker_faction == is_b_attacker_faction: continue # No friendly fire

			var can_a_attack_b = creature_a.can_attack(creature_b)
			var distance_ok = false
			var row_diff = abs(creature_a.row - creature_b.row)
			
			# Lane check: must be in same lane
			if creature_a.lane != creature_b.lane: continue

			# Row check for attacking
			# Assuming non-reach can only attack adjacent rows within their 3-row zone or the enemy's closest row
			var attack_reach = 1
			if creature_a.has_reach: attack_reach = TOTAL_GRID_ROWS # Simplification: reach can hit anyone in lane
			
			if row_diff <= attack_reach : # And creature_b is a valid target (e.g., not blocked by another unit in front)
				# Simple: if in range, can attack. More complex: check for blockers.
				# For now, if in range and can_attack is true, add to actions.
				if can_a_attack_b:
					combat_actions.append({"attacker": creature_a, "target": creature_b, "damage": creature_a.attack_power})
					# Typically one attack per creature per "round" of combat.
					# If creature_a attacks creature_b, it might not attack others this round.
					# This simplistic loop allows multiple targets if in range. Refine if needed.
					break # Creature A found a target this combat phase for its lane

	# Apply damage from actions
	for action in combat_actions:
		var attacker: Creature = action.attacker
		var target: Creature = action.target
		var damage: int = action.damage
		
		if is_instance_valid(attacker) and not attacker.is_dead() and \
		   is_instance_valid(target) and not target.is_dead():
			print("%s (at %d,%d) attacks %s (at %d,%d) for %d damage" % [
				attacker.get_class(), attacker.lane, attacker.row,
				target.get_class(), target.lane, target.row,
				damage
			])
			target.take_damage(damage) # take_damage should call handle_creature_death if health <= 0
	
	# After all combat actions, check game state (e.g., if all aliens died)
	check_game_state_after_combat()


func handle_creature_death(creature: Creature) -> void:
	var last_pos = Vector2(creature.lane, creature.row)
	battle_grid.remove_creature_from_coords(last_pos)

	# Store data for potential reanimation (if not undead with finality 0)
	var can_be_reanimated = true
	if creature is Undead:
		if creature.finality_counter <= 0: # Already used up finality during its 'die' call
			can_be_reanimated = false
	
	var creature_original_data_for_signal = {
		"attack": creature.attack_power, # Store stats at time of death
		"max_health": creature.max_health,
		"speed_type": creature.speed_type,
		"is_flying": creature.is_flying,
		"has_reach": creature.has_reach,
		"original_class_name": creature.get_class() # To know what it was
	}
	# This is the data the reanimation spell will use to determine stats of Zombie/Spirit
	var dead_info = {
		"data_for_signal": creature_original_data_for_signal, # For the signal
		"original_creature_node_for_stats": creature, # Direct ref for Undead.create_from_creature
		"position": last_pos,
		"time_of_death": Time.get_ticks_msec(),
	}

	if can_be_reanimated:
		dead_creatures_for_reanimation.append(dead_info)
		# TODO: Instance a clickable "CorpseNode" visually on the battle_grid
		# corpse_node.init(dead_info)

	# Remove from active lists
	if creature is Human:
		living_humans.erase(creature)
		human_population -= 1 # Or more, depending on creature value
		emit_signal("human_population_changed", human_population)
		if human_population <= 0:
			game_over(false) # Humans lost
	elif creature is Alien:
		living_aliens.erase(creature)
	elif creature is Undead:
		living_undead.erase(creature) # Already handled by its own die() if finality becomes 0

	# Signal that a creature died, passing its data too
	emit_signal("creature_died", creature, last_pos, creature_original_data_for_signal)
	
	# Original creature node is queued for deletion by its own die() method usually.
	# If not, queue_free it here:
	# creature.queue_free() # Ensure this doesn't happen twice
	
	# Check game state after death (e.g., if all aliens died)
	# This might be redundant if process_combat already calls it.
	if not (creature is Human and human_population <=0): # Avoid double game over call
		check_game_state_after_combat()


func undead_died_with_finality_remaining(undead_creature: Undead) -> void:
	# This undead "died" but has finality, so it effectively "resets" or "respawns"
	# It's removed from grid by its own die() method's call to handle_creature_death
	# then re-added here.
	print("%s respawns due to finality counter %d" % [undead_creature.get_class(), undead_creature.finality_counter])
	undead_creature.current_health = undead_creature.max_health # Restore health
	
	# Re-place it on the grid. It will try to find a spot like a new unit.
	if not spawn_creature_with_logic(undead_creature):
		print("Failed to respawn undead with finality: ", undead_creature.get_class())
		# If it can't be placed back, it's effectively lost for now.
		# Or, you might want to queue_free it and remove from living_undead.
		living_undead.erase(undead_creature)
		undead_creature.queue_free()


func undead_permanently_died(undead_creature: Undead) -> void:
	# This is called when finality_counter reaches 0.
	# Its removal from grid and living_undead list is handled by handle_creature_death.
	print("%s permanently destroyed (finality exhausted)." % undead_creature.get_class())
	# No re-adding to dead_creatures_for_reanimation.
	# The creature's queue_free is typically handled in its Creature.die() or Undead.die()

func reanimate_creature_from_data(dead_creature_info_from_signal: Dictionary, undead_type_string: String, necromancer_level: int) -> void:
	var found_and_removed = false
	for i in range(dead_creatures_for_reanimation.size() -1, -1, -1):
		if dead_creatures_for_reanimation[i] == dead_creature_info_from_signal: # Comparing dictionary instances
			dead_creatures_for_reanimation.remove_at(i)
			found_and_removed = true
			break
	
	if not found_and_removed:
		# Fallback: try to find by position if direct dict comparison fails (it often does for new dicts)
		var dead_pos = dead_creature_info_from_signal.get("position", Vector2.ONE * -1)
		if dead_pos != Vector2.ONE * -1:
			for i in range(dead_creatures_for_reanimation.size() -1, -1, -1):
				if dead_creatures_for_reanimation[i].position == dead_pos: # Check pos
					dead_creature_info_from_signal = dead_creatures_for_reanimation[i] # Use the stored one
					dead_creatures_for_reanimation.remove_at(i)
					found_and_removed = true
					break
	
	if not found_and_removed:
		print("Error: Dead creature data for reanimation not found or already used.")
		# Potentially refund DE to necromancer here
		return

	# TODO: Remove the clickable "CorpseNode" from the battle_grid

	var original_creature_node : Creature = dead_creature_info_from_signal.original_creature_node_for_stats

	var new_undead = Undead.create_from_creature(
		original_creature_node, # Pass the creature *instance* or a data structure of its relevant stats
		undead_type_string,
		necromancer_level
	)
	new_undead.name = undead_type_string + str(living_undead.size() + 1)

	if spawn_creature_with_logic(new_undead):
		print("Successfully reanimated %s as %s." % [original_creature_node.get_class(), undead_type_string])
		# Original creature node that died should have been queue_freed already
		# if not, and original_creature_node was just a data carrier, ensure it's cleaned up if needed.
	else:
		print("Failed to place reanimated %s." % undead_type_string)
		# Re-add to dead_creatures_for_reanimation if placement fails? Or DE refunded by Necromancer?
		# For now, if placement fails, it's lost.
		# dead_creatures_for_reanimation.append(dead_creature_info_from_signal) # Option: allow retry

func game_over(player_won: bool) -> void:
	is_wave_active = false
	wave_timer.stop()
	if player_won:
		print("CONGRATULATIONS! Earth is safe... for now.")
		# Show win screen, etc.
	else:
		print("GAME OVER. The swarm has consumed Earth.")
		# Show lose screen
	
	# get_tree().paused = true # Optional: pause game
	# Or: get_tree().change_scene_to_file("res://game_over_screen.tscn")


func get_creatures_in_lane(lane_idx: int) -> Array[Creature]:
	var creatures_in_lane = []
	for x in range(TOTAL_GRID_ROWS):
		var creature = battle_grid.get_creature_at_coords(Vector2(lane_idx, x))
		if creature != null:
			creatures_in_lane.append(creature)
	return creatures_in_lane
