# ./scripts/spells/SpellReanimateData.gd
extends SpellData
class_name SpellReanimateData

# Defines the Reanimate spell. Allows the Necromancer to raise Undead from corpses.
# The type of Undead created depends on the spell's level.

# --- UNDEAD TYPE MAPPING ---
# This could be more complex, e.g., allowing player choice if multiple types are unlocked.
# For now, spell_level maps directly:
const UNDEAD_TYPE_SKELETON = "Skeleton"
const UNDEAD_TYPE_ZOMBIE = "Zombie"
const UNDEAD_TYPE_SPIRIT = "Spirit"


func _init(config: Dictionary = {}):
	super._init(config) # Call parent constructor

	# Default values specific to Reanimate
	spell_name = config.get("spell_name", "Reanimate")
	spell_description = config.get("spell_description", "Raises a fallen creature as an Undead servant. Type depends on spell level.")
	de_cost = config.get("de_cost", 10) # Base DE cost, can be adjusted by level
	required_mc_level = config.get("required_mc_level", 1)
	spell_level = config.get("spell_level", 1)
	max_spell_level = config.get("max_spell_level", 3) # e.g., Lvl 1:Skel, Lvl 2:Zom, Lvl 3:Spirit
	target_type = TargetType.CORPSE


# Override can_cast for Reanimate-specific checks
func can_cast(caster_node, current_de: int, target_data = null) -> bool:
	if not super.can_cast(caster_node, current_de): # Check base conditions (DE, MC level)
		return false

	if not target_data is CorpseData:
		printerr("Reanimate: Invalid target. Expected CorpseData.")
		return false

	var corpse: CorpseData = target_data
	if not corpse.can_be_reanimated():
		# print_debug("Reanimate: Target corpse (Finality: %d) cannot be reanimated." % corpse.finality_counter)
		return false
	
	# Check if the chosen Undead type for the current spell level is valid (placeholder for future)
	var undead_type_to_create = get_undead_type_for_current_level()
	if undead_type_to_create == "":
		printerr("Reanimate: No valid Undead type defined for spell level %d." % spell_level)
		return false

	return true

# Override cast to handle the Reanimate spell's execution
func cast(caster_node, target_data = null) -> bool:
	# Ensure Necromancer and GameManager references are set (should be done by Necromancer node)
	if not is_instance_valid(caster) or not is_instance_valid(game_manager):
		printerr("Reanimate: Caster or GameManager reference not set in spell.")
		return false
	
	if not can_cast(caster_node, caster.current_de, target_data):
		return false

	# Apply DE cost
	caster.spend_de(de_cost)

	# Apply the reanimation effect
	var success = apply_effect(caster_node, target_data)
	
	if success:
		# print_debug("Reanimate cast successfully on corpse of '%s'." % [target_data.original_creature_name])
		pass # GameManager will handle UI updates for roster etc.
	else:
		# print_debug("Reanimate failed to apply effect.")
		# Potentially refund DE if apply_effect can fail after cost is paid (though unlikely here)
		pass
		
	return success

# Override apply_effect for the core reanimation logic
func apply_effect(caster_node, target_data = null) -> bool:
	var corpse: CorpseData = target_data
	if not is_instance_valid(corpse): # Should have been checked by can_cast
		return false

	var undead_type_to_create: String = get_undead_type_for_current_level()
	var new_undead_finality: int = corpse.finality_counter - 1 
	# This new_undead_finality is for the Undead *instance*. The corpse's finality was already >0.

	if new_undead_finality < 0:
		printerr("Reanimate Error: Calculated new Undead finality is less than 0. This shouldn't happen if corpse.can_be_reanimated() was true.")
		return false # Should not occur if can_be_reanimated (which checks finality > 0) was true

	var creature_config = {} # Dictionary to configure the new Undead

	match undead_type_to_create:
		UNDEAD_TYPE_SKELETON:
			creature_config = {
				"creature_class_script_path": "res://scripts/creatures/Skeleton.gd", # Path to Skeleton script
				"creature_name": "Skeleton",
				"max_health": 1,
				"attack_power": 1,
				"speed_type": Creature.SpeedType.NORMAL,
				"is_flying": false,
				"has_reach": false,
				"finality_counter": new_undead_finality
			}
		UNDEAD_TYPE_ZOMBIE:
			creature_config = {
				"creature_class_script_path": "res://scripts/creatures/Zombie.gd", # Path to Zombie script
				"creature_name": "Zombie (%s)" % corpse.original_creature_name, # e.g. "Zombie (Human Spearman)"
				"max_health": corpse.original_max_health,
				"attack_power": 1,
				"speed_type": Creature.SpeedType.SLOW,
				"is_flying": false,
				"has_reach": corpse.original_had_reach, # Zombies can inherit reach
				"finality_counter": new_undead_finality
			}
		UNDEAD_TYPE_SPIRIT:
			creature_config = {
				"creature_class_script_path": "res://scripts/creatures/Spirit.gd", # Path to Spirit script
				"creature_name": "Spirit of %s" % corpse.original_creature_name,
				"max_health": 1,
				"attack_power": corpse.original_attack_power, # Spirits inherit original attack
				"speed_type": Creature.SpeedType.FAST,
				"is_flying": true,
				"has_reach": false,
				"finality_counter": new_undead_finality
			}
		_:
			printerr("Reanimate: Unknown Undead type '%s' for spell level %d." % [undead_type_to_create, spell_level])
			return false
	
	# Delegate the actual instantiation and roster management to GameManager
	# GameManager will create a Node2D, attach the script, call initialize_creature, and add to roster.
	var new_undead_node = game_manager.spawn_reanimated_creature(creature_config)

	if is_instance_valid(new_undead_node):
		game_manager.consume_corpse(corpse) # Tell GameManager to remove the corpse from lists
		return true
	else:
		printerr("Reanimate: GameManager failed to spawn the reanimated creature.")
		return false


func get_undead_type_for_current_level() -> String:
	match spell_level:
		1:
			return UNDEAD_TYPE_SKELETON
		2:
			return UNDEAD_TYPE_ZOMBIE
		3: # And potentially higher levels if max_spell_level allows
			return UNDEAD_TYPE_SPIRIT
		_:
			return "" # No type defined for this level

# Override to provide valid targets for Reanimate
func get_valid_targets(caster_node, all_creatures: Array, all_corpses: Array) -> Array:
	var valid_targets: Array[CorpseData] = []
	if not is_instance_valid(game_manager):
		printerr("Reanimate/get_valid_targets: GameManager reference not set.")
		return valid_targets

	for corpse_resource in game_manager.get_available_corpses(): # Assumes GameManager has this method
		if corpse_resource is CorpseData and corpse_resource.can_be_reanimated():
			valid_targets.append(corpse_resource)
	return valid_targets

# Override to show level-specific spell description
func get_level_specific_description() -> String:
	var undead_type = get_undead_type_for_current_level()
	if undead_type == "":
		return "Raises a fallen creature as an Undead. (Invalid spell level for type selection)"
	return "Raises a %s from a corpse.\nConsumes 1 Finality from the corpse." % undead_type.to_lower()

# Override to handle spell upgrades
func upgrade_spell():
	if super.upgrade_spell(): # Call base to increment spell_level
		# Adjust DE cost or other properties based on new level, if desired
		match spell_level:
			1: de_cost = 10 
			2: de_cost = 12 # Example: Zombies might cost slightly more
			3: de_cost = 15 # Example: Spirits might cost more
			# Add cases for higher levels if max_spell_level is increased
		# print_debug("Reanimate upgraded. New DE cost: %d. Now summons: %s" % [de_cost, get_undead_type_for_current_level()])
		return true
	return false
