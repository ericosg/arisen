# GameManager.gd
class_name GameManager
extends Node

signal wave_started(wave_number)
signal wave_ended(wave_number)
signal human_population_changed(new_count)
signal creature_died(creature, position)

var human_population : int = 1000
var current_wave : int = 0
var necromancer : Node = null

# Containers for tracking creatures
var humans : Array[Human] = []
var aliens : Array[Alien] = []
var undead : Array[Undead] = []

func _ready() -> void:
	necromancer = get_node("Necromancer")

func start_wave() -> void:
	current_wave += 1
	emit_signal("wave_started", current_wave)
	# Spawn aliens based on current wave
	spawn_wave_aliens()

func end_wave() -> void:
	emit_signal("wave_ended", current_wave)
	# Replenish necromancer's dark energy
	if necromancer:
		necromancer.current_de = necromancer.max_de

func spawn_wave_aliens() -> void:
	# Example logic to spawn aliens based on wave number
	var base_count = 5 + current_wave * 2
	
	# Spawn different types of aliens with varying distributions
	for i in range(base_count):
		var type = randi() % 5
		var alien
		match type:
			0:
				alien = Alien.create_fireant()
			1:
				alien = Alien.create_wasp()
			2:
				alien = Alien.create_spider()
			3:
				alien = Alien.create_scorpion()
			4:
				alien = Alien.create_beetle()
		
		# Assign to a random row/lane based on speed
		alien.row = 0  # Start at the far end
		alien.lane = randi() % 5  # Random lane between 0-4
		
		aliens.append(alien)
		add_child(alien)

func spawn_humans(count: int) -> void:
	for i in range(count):
		var type = randi() % 5
		var human
		match type:
			0:
				human = Human.create_civilian()
			1:
				human = Human.create_spearman()
			2:
				human = Human.create_swordsman()
			3:
				human = Human.create_archer()
			4:
				human = Human.create_knight()
		
		# Assign to defensive rows/lanes
		human.row = 5  # Close to player's side
		human.lane = randi() % 5  # Random lane between 0-4
		
		humans.append(human)
		add_child(human)

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
		end_wave()

func undead_died_with_finality(undead: Undead) -> void:
	# Undead still has finality counters, can be respawned
	undead.current_health = undead.max_health
	emit_signal("creature_died", undead, Vector2(undead.lane, undead.row))

func undead_permanently_died(undead: Undead) -> void:
	undead.erase(undead)
	emit_signal("creature_died", undead, Vector2(undead.lane, undead.row))

func reanimate_at_position(position: Vector2, undead_type: String) -> void:
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
		necromancer.level
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
