# ./scripts/creatures/Zombie.gd
extends Undead
class_name Zombie

# Zombies are a specific type of Undead.
# Their unique stats (1 attack, original corpse max_health, SLOW speed,
# potentially inherits reach, no flying) are defined by the configuration
# dictionary passed to initialize_creature() when they are created by the ReanimateSpell.

func _init():
	# creature_name = "Zombie" # Will be set by config
	pass

func initialize_creature(config: Dictionary):
	# Ensure the config dictionary for a Zombie correctly sets its specific attributes:
	# config["creature_name"] = "Zombie" (or a variant)
	# config["max_health"] = (value from corpse.original_max_health)
	# config["attack_power"] = 1
	# config["speed_type"] = Creature.SpeedType.SLOW
	# config["is_flying"] = false
	# config["has_reach"] = (value from corpse.original_had_reach)
	# config["finality_counter"] = (value from corpse.finality_counter - 1)

	# Call the parent's initialize_creature method with the provided config.
	super.initialize_creature(config)

	# Any Zombie-specific initialization after the base setup.
	# For example, Zombies might have a unique visual shader or sound.
	# print_debug("Zombie '%s' fully initialized. Inherited reach: %s" % [creature_name, str(has_reach)])

# If Zombies had unique abilities (e.g., "Regeneration" per turn),
# those methods would be defined here.
# func regenerate_health(amount: int):
#    if is_alive:
#        _set_current_health(current_health + amount) # Uses setter from Creature.gd
#        print_debug("'%s' regenerates %d health. Current health: %d" % [creature_name, amount, current_health])
