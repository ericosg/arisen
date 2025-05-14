# ./scripts/creatures/Human.gd
extends Creature
class_name Human

# Humans are a specific faction of creatures.
# Their unique types (Civilian, Spearman, Swordsman, Archer, Knight)
# and corresponding stats/abilities are defined by the configuration
# dictionary passed to initialize_creature() when they are created.

func _init():
	# Human creatures always belong to the HUMAN faction.
	# Set this by default for any node this script is attached to.
	faction = Faction.HUMAN
	# creature_name = "Human" # Will be set by config typically

func initialize_creature(config: Dictionary):
	# Call the parent's initialize_creature method first.
	super.initialize_creature(config)

	# Ensure the faction is correctly set to HUMAN, overriding any config just in case.
	self.faction = Faction.HUMAN

	# Specific Human types (Civilian, Spearman, etc.) will have their attributes
	# (max_health, attack_power, speed_type, has_reach for Archers, etc.)
	# set by the 'config' dictionary.
	# This base Human.gd doesn't need to know those specifics, only that they come from config.
	
	# print_debug("Human creature '%s' initialized." % creature_name)

# If all Humans shared a specific ability (e.g., "Morale Boost" under certain conditions),
# that logic could be implemented here or in a more specific derived class if needed.
# For now, individual human types are distinguished by their configuration.

# The die() method from Creature.gd is inherited.
# When a Human dies, Creature.gd's die() method will emit the "died" signal.
# The GameManager will then create a CorpseData object. This corpse will be given
# an initial finality_counter by the GameManager or ReanimateSpell, allowing it
# to be reanimated into an Undead.
