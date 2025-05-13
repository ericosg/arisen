# Alien.gd - Base class for alien creatures
class_name Alien
extends Creature

func _init(attack: int = 1, health: int = 1, speed: int = SpeedType.NORMAL, flying: bool = false, reach: bool = false):
	super._init(attack, health, speed, flying, reach)
	creature_type = Type.ALIEN

func die() -> void:
	# Alien death logic - could emit a signal that an alien has died
	var game_manager = get_node("/root/GameManager")
	if game_manager:
		game_manager.alien_died(self)
	
	queue_free()

# Create the alien-specific types as static factory methods
static func create_fireant() -> Alien:
	return Alien.new(1, 1, SpeedType.FAST)

static func create_wasp() -> Alien:
	return Alien.new(2, 1, SpeedType.NORMAL, true)  # Flying

static func create_spider() -> Alien:
	return Alien.new(1, 2, SpeedType.NORMAL)

static func create_scorpion() -> Alien:
	return Alien.new(3, 2, SpeedType.NORMAL)

static func create_beetle() -> Alien:
	return Alien.new(2, 4, SpeedType.SLOW)
