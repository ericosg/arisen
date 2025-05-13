# Alien.gd - Base class for alien creatures
class_name Alien
extends Creature

func _init(ap: int = 1, hp: int = 1, spd: SpeedType = SpeedType.NORMAL, flying: bool = false, reach: bool = false):
	super._init(ap, hp, spd, flying, reach)
	faction = CreatureFaction.ALIEN

func die() -> void:
	# Alien-specific death effects
	print("Alien %s at %s,%s has been neutralized!" % [self.name, lane, row])

	# Signal to GameManager
	var game_manager = $GameManager
	if game_manager and game_manager.has_method("handle_creature_death"):
		game_manager.handle_creature_death(self)
		
	super.die() # This will call queue_free()

# --- Factory Methods ---
static func create_fireant() -> Alien: # High speed
	return Alien.new(2, 2, SpeedType.FAST)

static func create_wasp() -> Alien: # Flyers
	return Alien.new(3, 1, SpeedType.NORMAL, true)

static func create_spider() -> Alien:
	return Alien.new(2, 3, SpeedType.NORMAL)

static func create_scorpion() -> Alien:
	return Alien.new(4, 4, SpeedType.NORMAL) # Tougher normal speed

static func create_beetle() -> Alien: # Slow speed
	return Alien.new(3, 6, SpeedType.SLOW)
