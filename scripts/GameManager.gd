# GameManager.gd
extends Node

signal wave_started(wave_number)
signal wave_ended(wave_number)
signal wave_completed
signal human_population_changed(new_count)
signal creature_died(creature, position)
signal request_reanimate(position, undead_type)

const GRID_WIDTH = 10  # Columns/lanes
const GRID_HEIGHT = 6  # Rows

var human_population : int = 1000
var current_wave : int = 0
var is_wave_active : bool = false
var wave_timer : Timer = null

# Containers for tracking creatures
var humans : Array[Human] = []
var aliens : Array[Alien] = []
var undead : Array[Undead] = []

@onready var battle_grid = $BattleGrid

func _ready() -> void:
	wave_timer = Timer.new()
	wave_timer.one_shot = true
	wave_timer.wait_time = 5.0 # 5 seconds between waves
	wave_timer.connect("timeout", _on_wave_timer_timeout)
	add_child(wave_timer)
	
	# Connect signals from/to MainCharacter if needed
	var main_character = get_node_or_null("/root/MainScene/MainCharacter")
	if main_character:
		connect("wave_completed", main_character.update_de)
		connect("request_reanimate", main_character.cast_spell.bind(Spell.SpellType.REANIMATE))

func start_game() -> void:
	current_wave = 0
	human_population = 1000
	start_next_wave()

func start_next_wave() -> void:
	current_wave += 1
	is_wave_active = true
	emit_signal("wave_started", current_wave)
	spawn_wave_aliens()

func _on_wave_timer_timeout() -> void:
	start_next_wave()

func end_wave() -> void:
	emit_signal("wave_ended", current_wave)
	emit_signal("wave_completed")
	# DE replenishment is now handled by the MainCharacter

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

func human_died(human: Human) -> void:
	humans.erase(human)
	human_population -= 1
	emit_signal("human_population_changed", human_population)
	emit_signal("creature_died", human, Vector2(human.lane, human.row))
	
	if human_population <= 0:
		game_over()

func alien_died(alien: Alien) -> void:
	aliens.erase(alien)
	emit_signal("creature_died", alien, Vector2(alien.lane, alien.row))
	
	if aliens.size() == 0:
		check_wave_completion()

func undead_died_with_finality(undead: Undead) -> void:
	# Undead still has finality counters, can be respawned
	undead.current_health = undead.max_health
	emit_signal("creature_died", undead, Vector2(undead.lane, undead.row))

func undead_permanently_died(undead: Undead) -> void:
	undead.erase(undead)
	emit_signal("creature_died", undead, Vector2(undead.lane, undead.row))

func creature_died(creature) -> void:
	if battle_grid:
		var grid_pos = Vector2(creature.lane, creature.row)
		battle_grid.remove_creature(grid_pos)
	
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

func reanimate_at_position(position: Vector2, undead_type: String, necromancer_level: int = 1) -> void:
	var dead_creature = null
	
	# Check if there's a dead creature at this position
	for creature in get_creatures_at_position(position):
		if creature.is_dead():
			dead_creature = creature
			break
	
	if dead_creature == null:
		print("No dead creature found at position")
		return
	
	# Create appropriate undead type
	var new_undead = Undead.create_from_creature(
		dead_creature, 
		undead_type, 
		necromancer_level
	)
	
	# Set the same position
	new_undead.row = position.y
	new_undead.lane = position.x
	
	# Remove the dead creature
	if dead_creature is Human:
		humans.erase(dead_creature)
	elif dead_creature is Alien:
		aliens.erase(dead_creature)
	dead_creature.queue_free()
	
	print("🔮 Reanimated creature as %s at position %s" % [undead_type, position])
	
	# Add the new undead
	undead.append(new_undead)
	add_child(new_undead)

func get_creatures_at_position(position: Vector2) -> Array:
	var result = []
	for creature in humans + aliens + undead:
		if creature.lane == position.x and creature.row == position.y:
			result.append(creature)
	return result

func game_over() -> void:
	print("Game Over! Humans are extinct!")
	# Handle game over state
