# ./scripts/creatures/Undead.gd
extends Creature
class_name Undead

# Undead creatures have a finality counter.
# This script ensures Undead-specific initialization, faction setting,
# and manages the visibility and content of the finality counter UI.

# Signal for when finality counter changes specifically for Undead.
# Creature.gd has a general finality_counter setter, but this is more specific.
signal undead_finality_changed(undead_instance: Undead, new_finality: int)

func _init():
	# Undead creatures always belong to the UNDEAD faction.
	faction = Faction.UNDEAD
	# creature_name will be set by config, e.g., "Skeleton", "Zombie"

# Override initialize_creature to handle Undead-specific setup.
func initialize_creature(config: Dictionary):
	# Call the parent's initialize_creature method first.
	# This will set up common attributes and also call _setup_ui_elements from Creature.gd.
	super.initialize_creature(config)

	# Ensure the faction is correctly set to UNDEAD, overriding any config just in case.
	self.faction = Faction.UNDEAD

	# Finality counter is provided in the config by the ReanimateSpell.
	# The setter in Creature.gd (_set_finality_counter) will be called.
	# We ensure it's explicitly set here if not already by super.
	if config.has("finality_counter"):
		_set_finality_counter(config.get("finality_counter", 0))
	else: # Default if somehow not in config (should be)
		_set_finality_counter(0)
		
	# Make the finality label visible and update it for Undead creatures.
	if is_instance_valid(finality_label): # finality_label is inherited from Creature.gd
		finality_label.visible = true
		_update_finality_label_ui() # Ensure it shows the correct initial value

	# print_debug("Undead creature '%s' initialized. Finality: %d" % [creature_name, finality_counter])

# Override the setter for finality_counter to emit the Undead-specific signal
# and ensure UI updates.
func _set_finality_counter(value: int):
	var old_finality = finality_counter
	# Use super to call Creature.gd's setter logic (clamping, base UI update)
	super._set_finality_counter(value) 
	
	if old_finality != finality_counter: # Check if value actually changed
		emit_signal("undead_finality_changed", self, finality_counter)
		# The super call to _set_finality_counter in Creature.gd already calls _update_finality_label_ui,
		# but we ensure visibility is correct for Undead here.
		if is_instance_valid(finality_label):
			finality_label.visible = true # Ensure it's visible for Undead
			# _update_finality_label_ui() # Already called by super's setter.

# Method to increase the finality counter of this Undead creature.
func increase_finality_counter(amount: int):
	if not is_alive or amount <= 0: return
	_set_finality_counter(finality_counter + amount) # Use setter
	# print_debug("'%s' finality increased by %d. New finality: %d" % [creature_name, amount, finality_counter])

# Method to decrease the finality counter.
func decrease_finality_counter(amount: int):
	if not is_alive or amount <= 0: return
	_set_finality_counter(finality_counter - amount) # Use setter
	# print_debug("'%s' finality decreased by %d. New finality: %d" % [creature_name, amount, finality_counter])

# Override die() to ensure finality label is hidden if it wasn't by the base.
func die():
	super.die() # Call base class die method (handles hiding other UI, emitting signal)
	if is_instance_valid(finality_label):
		finality_label.visible = false # Explicitly hide on death for Undead too

# Ensure the finality label UI is updated correctly.
# This overrides the one in Creature.gd to ensure visibility for Undead.
func _update_finality_label_ui():
	if not is_instance_valid(finality_label): 
		# print_debug("Undead '%s': Finality label node invalid in _update_finality_label_ui." % creature_name)
		return
	
	if self.faction == Faction.UNDEAD and is_alive: # Only show for living Undead
		finality_label.text = str(finality_counter)
		finality_label.visible = true
	else:
		finality_label.visible = false

# Override to ensure all UI elements, including finality, are correctly updated/shown for Undead.
func _update_all_ui_elements():
	super._update_all_ui_elements() # Update stats, level, abilities from base
	_update_finality_label_ui() # Specifically update finality for Undead
