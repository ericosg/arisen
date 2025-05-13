# Human.gd - Base class for human creatures
class_name Human
extends Creature

func _init(ap: int = 1, hp: int = 1, spd: SpeedType = SpeedType.NORMAL, flying: bool = false, reach: bool = false):
	super._init(ap, hp, spd, flying, reach)
	faction = CreatureFaction.HUMAN

func die() -> void:
	# Human-specific death effects could go here before calling super or signaling
	print("Human %s at %s,%s has fallen!" % [self.name, lane, row])
	
	# Signal to GameManager that this human died.
	# GameManager will handle list removal, population update, and corpse creation.
	var game_manager = $GameManager
	if game_manager and game_manager.has_method("handle_creature_death"):
		game_manager.handle_creature_death(self)
	
	# Generic creature death handles queue_free if not Undead
	super.die() # This will call queue_free()


# --- Factory Methods ---
static func create_civilian() -> Human:
	return Human.new(1, 2, SpeedType.NORMAL)

static func create_spearman() -> Human: # High speed
	return Human.new(2, 3, SpeedType.FAST)

static func create_swordsman() -> Human:
	return Human.new(3, 4, SpeedType.NORMAL)

static func create_archer() -> Human: # Reach
	return Human.new(2, 2, SpeedType.NORMAL, false, true)

static func create_knight() -> Human: # Slow speed
	return Human.new(4, 6, SpeedType.SLOW)
