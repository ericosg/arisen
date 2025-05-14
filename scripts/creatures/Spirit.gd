# ./scripts/creatures/Spirit.gd
extends Undead
class_name Spirit

# Spirits are a specific type of Undead.
# Their unique stats (original corpse attack_power, 1 health, FAST speed,
# always flying, no reach by default) are defined by the configuration
# dictionary passed to initialize_creature() when they are created by the ReanimateSpell.

func _init():
	# creature_name = "Spirit" # Will be set by config
	pass

func initialize_creature(config: Dictionary):
	# Ensure the config dictionary for a Spirit correctly sets its specific attributes:
	# config["creature_name"] = "Spirit" (or a variant)
	# config["max_health"] = 1
	# config["attack_power"] = (value from corpse.original_attack_power, GDD says 0 if original was 0)
	# config["speed_type"] = Creature.SpeedType.FAST
	# config["is_flying"] = true # Spirits are always flying
	# config["has_reach"] = false # Typically spirits don't have reach, flying handles their engagement
	# config["finality_counter"] = (value from corpse.finality_counter - 1)

	# Call the parent's initialize_creature method with the provided config.
	super.initialize_creature(config)

	# Any Spirit-specific initialization after the base setup.
	# For example, Spirits might have a translucent visual effect.
	# print_debug("Spirit '%s' fully initialized. Attack: %d" % [creature_name, attack_power])

# If Spirits had unique abilities (e.g., "Incorporeal" - chance to dodge attacks),
# those methods would be defined here.
# func attempt_incorporeal_dodge() -> bool:
#    if randf() < 0.25: # 25% chance to dodge
#        print_debug("'%s' turns incorporeal and dodges an attack!" % creature_name)
#        return true
#    return false
