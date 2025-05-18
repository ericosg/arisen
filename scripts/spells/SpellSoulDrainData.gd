# ./scripts/spells/SpellSoulDrainData.gd
extends SpellData
class_name SpellSoulDrainData

# --- SPELL-SPECIFIC DATA ---
var de_costs_per_level: Array[int] # DE cost FOR CASTING AT L1, L2, L3, L4, L5

func _init():
	super._init() # Call base class _init

	# --- Define all specific properties for Soul Drain ---
	spell_name = "Soul Drain"
	spell_description = "Damages a living creature, restoring Dark Energy to the caster. Affects more targets at higher levels."
	required_mc_level = 1
	target_type = TargetType.ENEMY_CREATURE # Default, logic handles specific targeting

	# Define DE costs for casting AT each level (L1 to L5)
	de_costs_per_level = [8, 10, 12, 14, 16]

	# Define Mastery Point costs to upgrade TO L2, L3, L4, L5
	mastery_costs = [1, 2, 3, 4] 

	# Calculate max_spell_level based on mastery_costs array
	max_spell_level = mastery_costs.size() + 1
	
	# spell_level is already initialized to 1 by SpellData's _init()

# --- OVERRIDE REQUIRED METHODS ---

func get_current_de_cost() -> int:
	if spell_level - 1 >= 0 and spell_level - 1 < de_costs_per_level.size():
		return de_costs_per_level[spell_level - 1]
	else:
		printerr("SoulDrain '%s': Invalid spell_level %d for de_costs_per_level (size %d)." % [spell_name, spell_level, de_costs_per_level.size()])
		return 999 # Fallback high cost

func cast(caster_node, target_data = null) -> bool:
	if not is_instance_valid(caster) or not is_instance_valid(game_manager):
		printerr("SoulDrain '%s': Caster or GameManager reference not set." % spell_name)
		if is_instance_valid(caster_node) and caster_node.has_signal("spell_cast_failed"):
			caster_node.emit_signal("spell_cast_failed", spell_name, "Internal Error: Caster/GM missing.")
		return false

	if not can_cast(caster_node, caster.current_de, target_data):
		return false

	if not caster.spend_de(get_current_de_cost()):
		printerr("SoulDrain '%s': Failed to spend DE." % spell_name) 
		if is_instance_valid(caster_node) and caster_node.has_signal("spell_cast_failed"):
			caster_node.emit_signal("spell_cast_failed", spell_name, "Failed to spend DE.")
		return false
		
	var success = apply_effect(caster_node, target_data)
	
	if not success and (_get_num_targets_for_level() > 1 or target_data == null): 
		if is_instance_valid(caster_node) and caster_node.has_signal("spell_cast_failed"):
			caster_node.emit_signal("spell_cast_failed", spell_name, "No valid targets found for effect.")
	#else:
		# print_debug("SoulDrain '%s' cast success status: %s" % [spell_name, str(success)])

	return success

func apply_effect(_caster_node, target_data = null) -> bool:
	var damage_amount = _get_damage_for_level()
	var de_restored_per_hit = _get_de_restored_for_level()
	var num_targets_to_hit = _get_num_targets_for_level()
	var actual_targets_hit = 0

	if not is_instance_valid(game_manager): 
		printerr("SoulDrain '%s' apply_effect: GameManager reference is not valid." % spell_name)
		return false

	if num_targets_to_hit == 1: 
		if not target_data is Creature: 
			printerr("SoulDrain '%s' apply_effect (single target): Invalid target_data." % spell_name)
			return false 
		var creature_target: Creature = target_data
		
		# Re-validate for safety, though can_cast should cover it
		if is_instance_valid(creature_target) and creature_target.is_alive and \
		   creature_target.faction != Creature.Faction.UNDEAD and \
		   (creature_target.faction == Creature.Faction.HUMAN or creature_target.faction == Creature.Faction.ALIEN):
			# print_debug("SoulDrain '%s' hits %s for %d damage." % [spell_name, creature_target.creature_name, damage_amount])
			creature_target.take_damage(damage_amount)
			actual_targets_hit = 1
		# else: print_debug("SoulDrain '%s' apply_effect (single target): Target %s invalid or not alive." % [spell_name, str(target_data)])
	else: # AoE 
		var potential_targets: Array[Creature] = game_manager.get_all_living_humans_and_aliens()
		potential_targets.shuffle()
		
		var targets_to_actually_damage = min(potential_targets.size(), num_targets_to_hit)
		for i in range(targets_to_actually_damage):
			var random_target: Creature = potential_targets[i]
			# print_debug("SoulDrain '%s' (AoE) hits %s for %d damage." % [spell_name, random_target.creature_name, damage_amount])
			random_target.take_damage(damage_amount)
			actual_targets_hit += 1
			
	if actual_targets_hit > 0:
		var total_de_restored = de_restored_per_hit * actual_targets_hit
		caster.restore_de(total_de_restored)
		# print_debug("SoulDrain '%s' restored %d DE to caster." % [spell_name, total_de_restored])
	
	return actual_targets_hit > 0

# --- OVERRIDE OTHER OPTIONAL METHODS ---

# Override can_cast to add SoulDrain-specific target checks
func can_cast(caster_node, current_de_on_caster: int, target_data = null) -> bool:
	if not super.can_cast(caster_node, current_de_on_caster, target_data): 
		return false

	var num_targets_to_hit = _get_num_targets_for_level()
	if num_targets_to_hit == 1: # Single target mode
		if not target_data is Creature:
			if is_instance_valid(caster_node) and caster_node.has_signal("spell_cast_failed"):
				caster_node.emit_signal("spell_cast_failed", spell_name, "Invalid target. Expected a Creature.")
			# else: printerr("SoulDrain '%s' can_cast (single): Invalid target. Expected Creature." % spell_name)
			return false
		var creature_target: Creature = target_data
		if not is_instance_valid(creature_target) or not creature_target.is_alive:
			if is_instance_valid(caster_node) and caster_node.has_signal("spell_cast_failed"):
				caster_node.emit_signal("spell_cast_failed", spell_name, "Target creature is invalid or dead.")
			# else: printerr("SoulDrain '%s' can_cast (single): Target creature invalid/dead." % spell_name)
			return false
		if creature_target.faction == Creature.Faction.UNDEAD:
			if is_instance_valid(caster_node) and caster_node.has_signal("spell_cast_failed"):
				caster_node.emit_signal("spell_cast_failed", spell_name, "Cannot target Undead creatures.")
			return false
		if creature_target.faction != Creature.Faction.HUMAN && creature_target.faction != Creature.Faction.ALIEN:
			if is_instance_valid(caster_node) and caster_node.has_signal("spell_cast_failed"):
				caster_node.emit_signal("spell_cast_failed", spell_name, "Can only target Humans or Aliens.")
			return false
	else: # AoE mode
		if not is_instance_valid(game_manager): # game_manager is a property of SpellData
			if is_instance_valid(caster_node) and caster_node.has_signal("spell_cast_failed"):
				caster_node.emit_signal("spell_cast_failed", spell_name, "Internal Error: GameManager missing for AoE.")
			# else: printerr("SoulDrain '%s' can_cast (AoE): GameManager reference not set." % spell_name)
			return false
	return true

# --- Helper methods for level-based scaling ---
func _get_damage_for_level() -> int:
	match spell_level:
		1: return 5; 
		2: return 7; 
		3: return 9; 
		4: return 11; 
		5: return 13
		_: printerr("SoulDrain '%s': Invalid spell_level %d for _get_damage_for_level." % [spell_name, spell_level]); return 5 

func _get_de_restored_for_level() -> int:
	match spell_level:
		1: return 3; 
		2: return 4; 
		3: return 5; 
		4: return 6; 
		5: return 7
		_: printerr("SoulDrain '%s': Invalid spell_level %d for _get_de_restored_for_level." % [spell_name, spell_level]); return 3

func _get_num_targets_for_level() -> int:
	match spell_level:
		1: return 1; 
		2: return 2; 
		3: return 3; 
		4: return 4; 
		5: return 5
		_: printerr("SoulDrain '%s': Invalid spell_level %d for _get_num_targets_for_level." % [spell_name, spell_level]); return 1

func get_valid_targets(_caster_node, _all_creatures: Array, _all_corpses: Array) -> Array[Creature]:
	var valid_targets: Array[Creature] = []
	if not is_instance_valid(game_manager):
		printerr("SoulDrain '%s' get_valid_targets: GameManager reference not set." % spell_name)
		return valid_targets

	for creature in game_manager.get_all_living_humans_and_aliens(): 
		if is_instance_valid(creature) and creature.is_alive: 
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

func upgrade_spell() -> bool:
	if super.upgrade_spell(): # This increments spell_level in SpellData
		# print_debug("SoulDrain '%s' upgraded to L%d. DE cost: %d." % [spell_name, spell_level, get_current_de_cost()])
		return true
	return false
