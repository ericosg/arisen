# ./scripts/creatures/Undead.gd
extends Creature
class_name Undead

# Undead creatures have a finality counter, which is already defined in Creature.gd
# This script primarily ensures Undead-specific initialization and faction setting.

# Signal for when finality counter changes, could be useful for UI or other effects.
signal finality_changed(undead_instance: Undead, new_finality: int)

func _init():
	# Undead creatures always belong to the UNDEAD faction.
	# This is set here to ensure it's the default for any node this script is attached to,
	# even before initialize_creature is called.
	faction = Faction.UNDEAD

# Override initialize_creature to handle Undead-specific setup.
func initialize_creature(config: Dictionary):
	# Call the parent's initialize_creature method first to set up common attributes.
	super.initialize_creature(config)

	# Ensure the faction is correctly set to UNDEAD, overriding any config just in case.
	self.faction = Faction.UNDEAD 

	# The finality_counter should be provided in the config when an Undead is created.
	# This value is determined by the ReanimateSpell (corpse's finality - 1).
	# If not provided, it defaults to 0, meaning it cannot be reanimated further by default
	# unless a spell explicitly gave the corpse a starting finality.
	# The GDD implies the reanimation spell calculates this, so it should be in the config.
	self.finality_counter = config.get("finality_counter", 0) 
	emit_signal("finality_changed", self, self.finality_counter)

	# Undead types (Skeleton, Zombie, Spirit) will have their specific stats (health, attack),
	# speed, flying status, etc., set by the config passed from the ReanimateSpell.
	# For example, a Skeleton config would set max_health=1, attack_power=1.
	# A Zombie config would use original_max_health from the corpse for its health.
	# This base Undead.gd doesn't need to know those specifics, only that they come from config.

	# print_debug("Undead creature '%s' initialized. Finality: %d" % [creature_name, finality_counter])

# Method to increase the finality counter of this Undead creature.
# This would typically be called by a spell effect.
func increase_finality_counter(amount: int):
	if not is_alive: # Can only increase finality on living Undead
		return
	if amount <= 0:
		return

	self.finality_counter += amount
	# print_debug("'%s' finality increased by %d. New finality: %d" % [creature_name, amount, finality_counter])
	emit_signal("finality_changed", self, self.finality_counter)
	# Potentially update UI or visuals related to finality.

# Method to decrease the finality counter.
# The main decrease happens when a corpse is reanimated (corpse's finality - 1 = new Undead's finality).
# This method could be used by other spell effects if needed.
func decrease_finality_counter(amount: int):
	if not is_alive:
		return
	if amount <= 0:
		return
	
	self.finality_counter = max(0, self.finality_counter - amount) # Finality cannot go below 0
	# print_debug("'%s' finality decreased by %d. New finality: %d" % [creature_name, amount, finality_counter])
	emit_signal("finality_changed", self, self.finality_counter)


# The die() method from Creature.gd is inherited.
# When an Undead dies, Creature.gd's die() method will emit the "died" signal.
# The GameManager, upon receiving this signal for an Undead creature,
# will use its get_data_for_corpse_creation() method.
# Creature.gd's get_data_for_corpse_creation() already correctly includes
# the Undead's current finality_counter in the payload if its faction is UNDEAD.
# So, no override of die() or get_data_for_corpse_creation() is strictly needed here
# for the core finality-on-death mechanic.

# Example: If Undead had a specific visual cue for finality, you might connect here.
# func _on_finality_changed(new_finality):
#    if has_node("FinalitySpriteIndicator"):
#        # Update visual based on new_finality
#        pass
