# Undead.gd - Base class for undead creatures
class_name Undead
extends Creature

func _init(attack: int = 1, health: int = 1, speed: int = SpeedType.NORMAL, flying: bool = false, reach: bool = false, finality: int = 1):
	super._init(attack, health, speed, flying, reach)
	creature_type = Type.UNDEAD
	finality_counter = finality

func die() -> void:
	finality_counter -= 1
	
	if finality_counter <= 0:
		# If no more finality counters, the undead is truly dead
		var game_manager = get_node("/root/GameManager")
		if game_manager:
			game_manager.undead_permanently_died(self)
		queue_free()
	else:
		# Emit a signal that this undead needs to be replaced/respawned
		var game_manager = get_node("/root/GameManager")
		if game_manager:
			game_manager.undead_died_with_finality(self)

# Static methods to create undead from various creatures
static func create_from_creature(creature: Creature, undead_type: String, necromancer_level: int) -> Undead:
	match undead_type:
		"skeleton":
			return create_skeleton(necromancer_level)
		"zombie":
			return create_zombie(creature.max_health, necromancer_level)
		"spirit":
			return create_spirit(creature.attack_power, necromancer_level)
		_:
			return create_skeleton(necromancer_level)  # Default to skeleton

# Create the undead-specific types as static factory methods
static func create_skeleton(necromancer_level: int = 1) -> Undead:
	var finality = 1 + int(necromancer_level / 3)  # Every 3 levels adds 1 finality counter
	return Undead.new(1, 1, SpeedType.NORMAL, false, false, finality)

static func create_zombie(original_health: int, necromancer_level: int = 1) -> Undead:
	var finality = 1 + int(necromancer_level / 4)  # Every 4 levels adds 1 finality counter
	return Undead.new(1, original_health, SpeedType.SLOW, false, false, finality)

static func create_spirit(original_attack: int, necromancer_level: int = 1) -> Undead:
	var finality = 1 + int(necromancer_level / 5)  # Every 5 levels adds 1 finality counter
	return Undead.new(original_attack, 1, SpeedType.FAST, true, false, finality)

# Method to increase finality counter
func add_finality(amount: int) -> void:
	finality_counter += amount
