# ./scripts/creatures/Alien.gd
extends Creature
class_name Alien

# Aliens are a specific faction of creatures.
# Their unique types (FireAnt, Wasp, Spider, Scorpion, Beetle)
# and corresponding stats/abilities are defined by the configuration
# dictionary passed to initialize_creature() when they are created.

func _init():
	# Alien creatures always belong to the ALIEN faction.
	# Set this by default for any node this script is attached to.
	faction = Faction.ALIEN
	# creature_name = "Alien" # Will be set by config typically

func initialize_creature(config: Dictionary):
	# Call the parent's initialize_creature method first.
	super.initialize_creature(config)

	# Ensure the faction is correctly set to ALIEN, overriding any config just in case.
	self.faction = Faction.ALIEN

	# Specific Alien types (FireAnt, Wasp, etc.) will have their attributes
	# (max_health, attack_power, speed_type, is_flying for Wasps, etc.)
	# set by the 'config' dictionary.
	# This base Alien.gd doesn't need to know those specifics, only that they come from config.

	# print_debug("Alien creature '%s' initialized." % creature_name)

# If all Aliens shared a specific ability (e.g., "Hive Mind Bonus" under certain conditions),
# that logic could be implemented here.
# For now, individual alien types are distinguished by their configuration.

# The die() method from Creature.gd is inherited.
# When an Alien dies, Creature.gd's die() method will emit the "died" signal.
# The GameManager will then create a CorpseData object. This corpse will be given
# an initial finality_counter, allowing it to be reanimated into an Undead.
