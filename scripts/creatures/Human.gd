# Human.gd - Base class for human creatures
class_name Human
extends Creature

func _init(attack: int = 1, health: int = 1, speed: int = SpeedType.NORMAL, flying: bool = false, reach: bool = false).(attack, health, speed, flying, reach) -> void:
	creature_type = Type.HUMAN

func die() -> void:
	# Human death logic - could emit a signal that a human has died
	var game_manager = get_node("/root/GameManager")
	if game_manager:
		game_manager.human_died(self)
	
	queue_free()

# Create the human-specific types as static factory methods
static func create_civilian() -> Human:
	return Human.new(1, 1, SpeedType.NORMAL)

static func create_spearman() -> Human:
	return Human.new(2, 2, SpeedType.FAST)

static func create_swordsman() -> Human:
	return Human.new(3, 2, SpeedType.NORMAL)

static func create_archer() -> Human:
	var archer = Human.new(2, 1, SpeedType.NORMAL, false, true)  # Has reach
	return archer

static func create_knight() -> Human:
	return Human.new(4, 4, SpeedType.SLOW)
