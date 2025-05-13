# GameManager.gd
extends Node

signal wave_started(wave_number)
signal wave_ended(wave_number)
signal wave_completed
signal human_population_changed(new_count)
signal creature_died(creature, position)
signal request_reanimate(position, undead_type)
signal turn_started(turn_number)
signal turn_ended(turn_number)

const GRID_WIDTH = 10  # Columns/lanes
const GRID_HEIGHT = 6  # Rows

var human_population : int = 1000
var current_wave : int = 0
var is_wave_active : bool = false
var wave_timer : Timer = null

# Turn-based game structure
var current_turn : int = 0
var waves_per_turn : int = 3
var current_wave_in_turn : int = 0

# Containers for tracking creatures
var humans : Array[Human] = []
var aliens : Array[Alien] = []
var undead : Array[Undead] = []
var dead_creatures = []  # Track dead creatures for reanimation

@onready var battle_grid = $BattleGrid

func _ready() -> void:
	print("arisen")
	wave_timer = Timer.new()
	wave_timer.one_shot = true
	wave_timer.wait_time = 5.0 # 5 seconds between waves
	wave_timer.connect("timeout", _on_wave_timer_timeout)
	add_child(wave_timer)
	
	# Connect signals from/to Necromancer if needed
	var necromancer = get_node_or_null("/root/MainScene/Necromancer")
	if necromancer:
		connect("wave_completed", necromancer.update_de)
		connect("request_reanimate", necromancer.cast_spell.bind(Spell.SpellType.REANIMATE))

func start_game() -> void:
	print("arise!")
	current_turn = 0
	current_wave_in_turn = 0
	current_wave = 0
	human_population = 1000
	start_next_turn()

func start_next_turn() -> void:
	current_turn += 1
	current_wave_in_turn = 0
	
	# Replenish DE at the start of a turn
	var necromancer = get_node_or_null("/root/MainScene/Necromancer")
	if necromancer:
		necromancer.current_de = necromancer.max_de
		necromancer._update_ui()
	
	emit_signal("turn_started", current_turn)
	start_next_wave()

func start_next_wave() -> void:
	current_wave += 1
	current_wave_in_turn += 1
	is_wave_active = true
	emit_signal("wave_started", current_wave)
	spawn_wave_aliens()

func _on_wave_timer_timeout() -> void:
	if current_wave_in_turn >= waves_per_turn:
		# End of turn
		emit_signal("turn_ended", current_turn)
		start_next_turn()
	else:
		# More waves in this turn
		start_next_wave()

func end_wave() -> void:
	emit_signal("wave_ended", current_wave)
	emit_signal("wave_completed")
	
	# Process movement after a wave ends
	move_creatures()
	
	# Process combat after movement
	process_combat()

func check_wave_completion() -> void:
	if aliens.size() == 0 and is_wave_active:
		is_wave_active = false
		end_wave()
		wave_timer.start()

func spawn_wave_aliens() -> void:
	var base_count = 5 + current_wave * 2
	
	for i in range(base_count):
		var type = randi() % 5
		var alien
		match type:
			0: alien = Alien.create_fireant()
			1: alien = Alien.create_wasp()
			2: alien = Alien.create_spider()
			3: alien = Alien.create_scorpion()
			4: alien = Alien.create_beetle()
		
		# Try to place at a valid position
		var lane = randi() % GRID_WIDTH
		var row = 0  # Start at the top
		
		# Add to scene first so it's properly initialized
		add_child(alien)
		aliens.append(alien)
		
		# Then place on grid
		if battle_grid and not battle_grid.place_creature(alien, Vector2(lane, row)):
			# If can't place, try nearby cells
			var placed = false
			for offset_x in range(-1, 2):
				for offset_y in range(0, 2):  # Only try current row or next row down
					var new_pos = Vector2(lane + offset_x, row + offset_y)
					if battle_grid.place_creature(alien, new_pos):
						placed = true
						break
				if placed:
					break
			
			if not placed:
				# If still couldn't place, remove the alien
				aliens.erase(alien)
				alien.queue_free()

# Moves creatures based on their speed
func move_creatures() -> void:
	# Move aliens down
	for alien in aliens:
		var move_distance = alien.get_move_distance()
		var new_row = min(alien.row + move_distance, GRID_HEIGHT - 1)
		
		if new_row != alien.row:
			# Remove from current position
			battle_grid.remove_creature(Vector2(alien.lane, alien.row))
			
			# Check if new position is available
			if battle_grid.place_creature(alien, Vector2(alien.lane, new_row)):
				print("Alien moved from row %d to %d" % [alien.row, new_row])
			else:
				# If blocked, try to find a nearby available position
				var placed = false
				for offset_y in range(move_distance, 0, -1):
					var try_row = min(alien.row + offset_y, GRID_HEIGHT - 1)
					if battle_grid.place_creature(alien, Vector2(alien.lane, try_row)):
						placed = true
						break
				
				if not placed:
					# If still can't place, stay at current position
					battle_grid.place_creature(alien, Vector2(alien.lane, alien.row))

# Process combat between creatures
func process_combat() -> void:
	# Process attacks for all lanes
	for lane in range(GRID_WIDTH):
		# First, aliens attack if there are any in this lane
		var lane_aliens = []
		for alien in aliens:
			if alien.lane == lane:
				lane_aliens.append(alien)
		
		# Sort aliens by row (top to bottom)
		lane_aliens.sort_custom(func(a, b): return a.row < b.row)
		
		# Then find potential human/undead targets
		var lane_defenders = []
		for creature in humans + undead:
			if creature.lane == lane:
				lane_defenders.append(creature)
		
		# Sort defenders by row (top to bottom)
		lane_defenders.sort_custom(func(a, b): return a.row < b.row)
		
		# Process attacks
		for attacker in lane_aliens:
			var found_target = false
			for defender in lane_defenders:
				# Check if attacker can attack defender
				if (attacker.can_attack(defender) and 
					defender.can_defend_against(attacker) and
					abs(attacker.row - defender.row) <= 1):  # Adjacent rows only
					
					# Apply damage
					defender.take_damage(attacker.attack_power)
					print("%s attacked %s for %d damage" % [
						attacker.get_class(),
						defender.get_class(),
						attacker.attack_power
					])
					found_target = true
					break
			
			# If no target found and alien is at bottom row, damage human population
			if not found_target and attacker.row == GRID_HEIGHT - 1:
				human_population -= attacker.attack_power
				emit_signal("human_population_changed", human_population)
				if human_population <= 0:
					game_over()
		
		# Now defenders attack back
		for defender in lane_defenders:
			for attacker in lane_aliens:
				# Check if defender can attack alien
				if (defender.can_attack(attacker) and 
					attacker.can_defend_against(defender) and
					abs(defender.row - attacker.row) <= 1):  # Adjacent rows only
					
					# Apply damage
					attacker.take_damage(defender.attack_power)
					print("%s attacked %s for %d damage" % [
						defender.get_class(),
						attacker.get_class(),
						defender.attack_power
					])
					break

func spawn_humans(count: int) -> void:
	for i in range(count):
		var type = randi() % 5
		var human
		match type:
			0: human = Human.create_civilian()
			1: human = Human.create_spearman()
			2: human = Human.create_swordsman()
			3: human = Human.create_archer()
			4: human = Human.create_knight()
		
		# Try to place at bottom rows
		var lane = randi() % GRID_WIDTH
		var row = GRID_HEIGHT - 1  # Bottom row
		
		# Add to scene first
		add_child(human)
		humans.append(human)
		
		# Then place on grid
		if battle_grid and not battle_grid.place_creature(human, Vector2(lane, row)):
			# Try rows above if bottom is full
			var placed = false
			for try_row in range(GRID_HEIGHT - 2, GRID_HEIGHT / 2, -1):
				if battle_grid.place_creature(human, Vector2(lane, try_row)):
					placed = true
					break
			
			if not placed:
				humans.erase(human)
				human.queue_free()

func handle_creature_death(creature) -> void:
	if battle_grid:
		var grid_pos = Vector2(creature.lane, creature.row)
		battle_grid.remove_creature(grid_pos)
	
	# Store dead creature for potential reanimation
	dead_creatures.append({
		"creature": creature,
		"position": Vector2(creature.lane, creature.row),
		"time_of_death": Time.get_ticks_msec()
	})
	
	emit_signal("creature_died", creature, Vector2(creature.lane, creature.row))
	
	if creature is Human:
		humans.erase(creature)
		human_population -= 1
		emit_signal("human_population_changed", human_population)
		
		if human_population <= 0:
			game_over()
	
	elif creature is Alien:
		aliens.erase(creature)
		
		if aliens.size() == 0:
			check_wave_completion()
	
	elif creature is Undead:
		undead.erase(creature)

func undead_died_with_finality(undead: Undead) -> void:
	# Remove from grid
	battle_grid.remove_creature(Vector2(undead.lane, undead.row))
	
	# Set health back to full
	undead.current_health = undead.max_health
	
	# Place back on grid
	battle_grid.place_creature(undead, Vector2(undead.lane, undead.row))
	
	emit_signal("creature_died", undead, Vector2(undead.lane, undead.row))

func undead_permanently_died(undead: Undead) -> void:
	undead.erase(undead)
	emit_signal("creature_died", undead, Vector2(undead.lane, undead.row))

func reanimate_at_position(position: Vector2, undead_type: String, necromancer_level: int = 1) -> void:
	# Look for recently dead creatures at this position
	var dead_creature_data = null
	var current_time = Time.get_ticks_msec()
	
	for i in range(dead_creatures.size() - 1, -1, -1):
		var data = dead_creatures[i]
		if data["position"] == position:
			# Found a dead creature at this position
			dead_creature_data = data
			dead_creatures.remove_at(i)
			break
	
	if not dead_creature_data:
		print("No dead creature found at position")
		return
	
	var dead_creature = dead_creature_data["creature"]
	
	# Create appropriate undead type
	var new_undead = Undead.create_from_creature(
		dead_creature, 
		undead_type, 
		necromancer_level
	)
	
	# Set the same position
	new_undead.row = position.y
	new_undead.lane = position.x
	
	# Add the new undead
	add_child(new_undead)
	undead.append(new_undead)
	battle_grid.place_creature(new_undead, position)
	
	print("🔮 Reanimated creature as %s at position %s" % [undead_type, position])

func get_creatures_at_position(position: Vector2) -> Array:
	var result = []
	for creature in humans + aliens + undead:
		if creature.lane == position.x and creature.row == position.y:
			result.append(creature)
	return result

func game_over() -> void:
	print("Game Over! Humans are extinct!")
	# Handle game over state
