# ./scripts/creatures/Skeleton.gd
extends Undead
class_name Skeleton

# Skeletons are a specific type of Undead.
# Their unique stats (1/1, normal speed, no flying/reach) are defined
# by the configuration dictionary passed to initialize_creature()
# when they are created by the ReanimateSpell.

func _init():
	# You can set a default creature_name here if desired,
	# but initialize_creature will typically override it.
	# creature_name = "Skeleton"
	pass

# Override initialize_creature if Skeletons have any truly unique initialization
# logic beyond what's handled by the config dictionary.
# For now, the standard Undead initialization is sufficient.
func initialize_creature(config: Dictionary):
	# Ensure the config dictionary for a Skeleton correctly sets its specific attributes:
	# config["creature_name"] = "Skeleton" (or a variant)
	# config["max_health"] = 1
	# config["attack_power"] = 1
	# config["speed_type"] = Creature.SpeedType.NORMAL
	# config["is_flying"] = false
	# config["has_reach"] = false
	# config["finality_counter"] = (value from corpse.finality_counter - 1)
	
	# Call the parent's initialize_creature method with the provided config.
	super.initialize_creature(config)
	
	# Any Skeleton-specific initialization after the base setup can go here.
	# For example, if Skeletons had a unique visual effect or sound on creation.
	# print_debug("Skeleton '%s' fully initialized." % creature_name)

# If Skeletons had unique abilities or behaviors, those methods would be defined here.
# For example:
# func perform_bone_rattle_ability():
#     print_debug("'%s' rattles its bones menacingly!" % creature_name)
