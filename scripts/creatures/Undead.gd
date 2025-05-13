# Undead.gd - Base class for undead creatures
class_name Undead
extends Creature

@export var original_creature_class_name: String = "" # What it was before (e.g., "Human", "Alien")
# finality_counter is inherited from Creature, default 0. Set it in constructor or factory.

func _init(ap: int = 1, hp: int = 1, spd: SpeedType = SpeedType.NORMAL, flying: bool = false, reach: bool = false, finality: int = 1, orig_class: String = ""):
	super._init(ap, hp, spd, flying, reach)
	faction = CreatureFaction.UNDEAD # Undead fight for the player (defender side)
	finality_counter = finality
	original_creature_class_name = orig_class

func die() -> void:
	finality_counter -= 1
	print("Undead %s at %s,%s was struck down. Finality: %d -> %d" % [self.name, lane, row, finality_counter + 1, finality_counter])

	var game_manager = $GameManager
	if not game_manager:
		printerr("Undead cannot find GameManager to report death!")
		queue_free() # Failsafe cleanup
		return

	if finality_counter < 0: # Should be <= 0, but <0 if init with 0 and dies.
		print("%s crumbles to dust (finality exhausted)." % self.name)
		game_manager.undead_permanently_died(self) # Inform GM
		game_manager.handle_creature_death(self) # Standard death processing (remove from lists etc)
		queue_free() # Undead handles its own queue_free
	else:
		print("%s will rise again (finality: %d remaining)." % [self.name, finality_counter])
		# It doesn't "die" in terms of game lists yet, it "respawns".
		# GameManager needs to handle its re-placement.
		# Remove from grid temporarily before re-placement attempt.
		game_manager.battle_grid.remove_creature_from_coords(Vector2(lane, row))
		game_manager.undead_died_with_finality_remaining(self)
		# DO NOT call super.die() or queue_free() here, as it's respawning.

# Static factory method to create undead from a former living creature's data
# original_creature_for_stats: This should be the Creature *instance* that died,
# or a dictionary holding its relevant stats (attack_power, max_health, speed_type, is_flying, has_reach, get_class())
static func create_from_creature(original_creature_for_stats: Creature, undead_type_str: String, necromancer_level: int) -> Undead:
	var new_undead: Undead
	
	var base_ap = original_creature_for_stats.attack_power
	var base_hp = original_creature_for_stats.max_health
	var base_speed = original_creature_for_stats.speed_type
	var base_flying = original_creature_for_stats.is_flying
	var base_reach = original_creature_for_stats.has_reach
	var base_class_name = original_creature_for_stats.get_class() # What it was

	var finality_bonus = int(necromancer_level / 3) # Example: +1 finality every 3 necro levels

	match undead_type_str.to_lower():
		"skeleton":
			# Skeletons are 1/1 but might inherit reach. Speed Normal.
			new_undead = Undead.new(1, 1, SpeedType.NORMAL, false, base_reach, 1 + finality_bonus, base_class_name)
		"zombie":
			# Zombies are 1/Y (original max health), speed reduced, might inherit reach.
			new_undead = Undead.new(1, base_hp, SpeedType.SLOW, false, base_reach, 1 + finality_bonus, base_class_name)
		"spirit":
			# Spirits are X/1 (original attack power), fast, flying, might inherit reach.
			new_undead = Undead.new(base_ap, 1, SpeedType.FAST, true, base_reach, 1 + finality_bonus, base_class_name)
		_: # Default to skeleton if type is unknown
			printerr("Unknown undead type requested: %s. Defaulting to Skeleton." % undead_type_str)
			new_undead = Undead.new(1, 1, SpeedType.NORMAL, false, base_reach, 1 + finality_bonus, base_class_name)
	
	return new_undead

func add_finality(amount: int) -> void:
	finality_counter += amount
	print("%s gained %d finality. Total: %d" % [self.name, amount, finality_counter])
