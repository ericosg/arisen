# ./scripts/spells/SpellSoulDrain.gd
extends SpellData
class_name SpellSoulDrainData

# Defines the Soul Drain spell. Damages living creatures and restores DE to the caster.
# Can target allied Humans or enemy Aliens. Does not target Undead.
# Becomes AoE at higher spell levels.

func _init(config: Dictionary = {}):
	super._init(config) # Call parent constructor

	# Default values specific to Soul Drain
	spell_name = config.get("spell_name", "Soul Drain")
	spell_description = config.get("spell_description", "Damages a living creature, restoring Dark Energy to the caster. Affects more targets at higher levels.")
	de_cost = config.get("de_cost", 8) # Base DE cost
	required_mc_level = config.get("required_mc_level", 1)
	spell_level = config.get("spell_level", 1)
	max_spell_level = config.get("max_spell_level", 5) # Example max level
	
	# Target type can be tricky: it's a creature, but if AoE, no specific target is pre-selected.
	# Let's say it's ENEMY_CREATURE for single target, and for AoE it will pick from valid types.
	# Or perhaps a new TargetType like ANY_LIVING_NON_UNDEAD.
	# For now, let's use ENEMY_CREATURE and handle allied human targeting in logic.
	# Or, if level 1 is single target, it might be ENEMY_CREATURE or ALLY_CREATURE.
	# If AoE, target_type might be NONE or a special AoE type.
	# Let's simplify: if it needs a specific target (level 1), it's CREATURE. Otherwise, NONE.
	target_type = TargetType.ENEMY_CREATURE # Default for Lvl 1, can also hit ALLY_CREATURE (Humans)


# Override can_cast for SoulDrain-specific checks
func can_cast(caster_node, current_de: int, target_data = null) -> bool:
	if not super.can_cast(caster_node, current_de): # Check base conditions (DE, MC level)
		return false

	# At level 1 (single target), a target is required.
	# At higher levels (AoE), target_data might be null as it hits multiple.
	var num_targets_to_hit = _get_num_targets_for_level()
	if num_targets_to_hit == 1: # Single target mode
		if not target_data is Creature:
			printerr("Soul Drain (Single Target): Invalid target. Expected a Creature.")
			return false
		var creature_target: Creature = target_data
		if not is_instance_valid(creature_target) or not creature_target.is_alive:
			printerr("Soul Drain (Single Target): Target creature is invalid or dead.")
			return false
		if creature_target.faction == Creature.Faction.UNDEAD:
			# print_debug("Soul Drain (Single Target): Cannot target Undead creatures.")
			return false
		# Can target HUMAN or ALIEN
		if creature_target.faction != Creature.Faction.HUMAN && creature_target.faction != Creature.Faction.ALIEN:
			printerr("Soul Drain (Single Target): Can only target Humans or Aliens.")
			return false
	else: # AoE mode, no specific single target needed at cast time, but game_manager must be valid
		if not is_instance_valid(game_manager):
			printerr("Soul Drain (AoE): GameManager reference not set, cannot find targets.")
			return false
			
	return true

# Override cast to handle the Soul Drain spell's execution
func cast(caster_node, target_data = null) -> bool:
	if not is_instance_valid(caster) or not is_instance_valid(game_manager):
		printerr("Soul Drain: Caster or GameManager reference not set in spell.")
		return false

	if not can_cast(caster_node, caster.current_de, target_data):
		return false

	caster.spend_de(de_cost)
	var success = apply_effect(caster_node, target_data)
	
	# No explicit success/failure message here, apply_effect will print debugs
	return success

# Override apply_effect for the core Soul Drain logic
func apply_effect(caster_node, target_data = null) -> bool:
	var damage_amount = _get_damage_for_level()
	var de_restored_per_hit = _get_de_restored_for_level()
	var num_targets_to_hit = _get_num_targets_for_level()
	var actual_targets_hit = 0

	if num_targets_to_hit == 1: # Single target
		if not target_data is Creature: return false # Should be caught by can_cast
		var creature_target: Creature = target_data
		
		# Double check validity (already done in can_cast for single target)
		if not is_instance_valid(creature_target) or not creature_target.is_alive or \
		   creature_target.faction == Creature.Faction.UNDEAD or \
		   (creature_target.faction != Creature.Faction.HUMAN and creature_target.faction != Creature.Faction.ALIEN):
			printerr("Soul Drain (Single Target): Invalid target in apply_effect.")
			return false

		# print_debug("Soul Drain hits %s (Faction: %s) for %d damage." % [creature_target.creature_name, Creature.Faction.keys()[creature_target.faction], damage_amount])
		creature_target.take_damage(damage_amount)
		actual_targets_hit = 1
	else: # AoE target
		var potential_targets: Array[Creature] = []
		# Assumes game_manager has these lists populated
		for creature in game_manager.get_all_living_humans_and_aliens(): # Needs method in GameManager
			if is_instance_valid(creature) and creature.is_alive: # Redundant check if list is clean
				potential_targets.append(creature)
		
		potential_targets.shuffle()
		
		var targets_to_actually_damage = min(potential_targets.size(), num_targets_to_hit)
		for i in range(targets_to_actually_damage):
			var random_target: Creature = potential_targets[i]
			# print_debug("Soul Drain (AoE) hits %s (Faction: %s) for %d damage." % [random_target.creature_name, Creature.Faction.keys()[random_target.faction], damage_amount])
			random_target.take_damage(damage_amount)
			actual_targets_hit += 1
			
	if actual_targets_hit > 0:
		var total_de_restored = de_restored_per_hit * actual_targets_hit
		caster.restore_de(total_de_restored)
		# print_debug("Soul Drain restored %d DE to caster." % total_de_restored)
	
	return actual_targets_hit > 0


# --- Helper methods for level-based scaling ---
func _get_damage_for_level() -> int:
	match spell_level:
		1: return 5
		2: return 7
		3: return 9
		4: return 11
		5: return 13
		_: return 5 # Default for invalid levels

func _get_de_restored_for_level() -> int:
	match spell_level:
		1: return 3
		2: return 4
		3: return 5
		4: return 6
		5: return 7
		_: return 3

func _get_num_targets_for_level() -> int:
	# Level 1 is single target. Higher levels hit more.
	match spell_level:
		1: return 1 
		2: return 2 # Hits up to 2 random valid targets
		3: return 3 # Hits up to 3
		4: return 4
		5: return 5
		_: return 1


# Override to provide valid targets for Soul Drain
func get_valid_targets(caster_node, all_creatures: Array, all_corpses: Array) -> Array:
	var valid_targets: Array[Creature] = []
	if not is_instance_valid(game_manager):
		printerr("SoulDrain/get_valid_targets: GameManager reference not set.")
		return valid_targets

	# This method is primarily for UI to show potential single targets.
	# For AoE, it might just show all possible targets that *could* be hit.
	for creature in game_manager.get_all_living_humans_and_aliens(): # Needs method in GameManager
		if is_instance_valid(creature) and creature.is_alive: # Already filtered by the GM method hopefully
			valid_targets.append(creature)
	return valid_targets


func get_level_specific_description() -> String:
	var damage = _get_damage_for_level()
	var de_gain = _get_de_restored_for_level()
	var num_targets = _get_num_targets_for_level()
	var target_desc = "a living Human or Alien creature"
	if num_targets > 1:
		target_desc = "up to %d random living Human or Alien creatures" % num_targets
	
	return "Deals %d damage to %s.\nRestores %d DE to caster for each target hit." % [damage, target_desc, de_gain]

func upgrade_spell():
	if super.upgrade_spell(): # Call base to increment spell_level
		# DE cost could also scale, e.g., more targets = higher cost
		match spell_level:
			1: de_cost = 8
			2: de_cost = 10 # Cost for hitting 2 targets
			3: de_cost = 12 # Cost for hitting 3 targets
			4: de_cost = 14
			5: de_cost = 16
		# print_debug("Soul Drain upgraded. New DE cost: %d. Damage: %d. Targets: %d. DE Restored/Hit: %d" % [de_cost, _get_damage_for_level(), _get_num_targets_for_level(), _get_de_restored_for_level()])
		return true
	return false
