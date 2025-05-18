# ./scripts/spells/SpellReanimateData.gd
extends SpellData
class_name SpellReanimateData

enum ReanimateSubtype { SKELETON, ZOMBIE, SPIRIT }

# --- SPELL-SPECIFIC DATA ---
# Base DE cost for each subtype
var subtype_base_de_costs: Dictionary = {
	ReanimateSubtype.SKELETON: 10,
	ReanimateSubtype.ZOMBIE: 12, # Was 15, adjusted to be different from Spirit
	ReanimateSubtype.SPIRIT: 15
}

# Minimum Reanimate spell level required to unlock each subtype
var subtype_unlock_level: Dictionary = {
	ReanimateSubtype.SKELETON: 1,
	ReanimateSubtype.ZOMBIE: 2,
	ReanimateSubtype.SPIRIT: 3
}

# Names for UI
var subtype_names: Dictionary = {
	ReanimateSubtype.SKELETON: "Skeleton",
	ReanimateSubtype.ZOMBIE: "Zombie",
	ReanimateSubtype.SPIRIT: "Spirit"
}


func _init():
	super._init() 

	spell_name = "Reanimate"
	spell_description = "Raises a fallen creature as an Undead servant. Type and cost depend on selection and spell level."
	required_mc_level = 1
	target_type = TargetType.CORPSE 

	mastery_costs = [2, 3] # MP cost to upgrade Reanimate spell TO L2, then TO L3
	max_spell_level = mastery_costs.size() + 1 # Max level for the Reanimate spell itself (3)

# --- OVERRIDE REQUIRED METHODS ---

# spell_specific_arg here is the selected_subtype (enum value)
func get_current_de_cost(selected_subtype = null) -> int:
	if selected_subtype == null: # Default to Skeleton if no subtype provided
		selected_subtype = ReanimateSubtype.SKELETON 
		# print_debug("Reanimate get_current_de_cost: No subtype provided, defaulting to Skeleton.")
	
	if not selected_subtype is ReanimateSubtype:
		printerr("Reanimate get_current_de_cost: Invalid selected_subtype type.")
		return 999

	if spell_level < subtype_unlock_level.get(selected_subtype, 99):
		# print_debug("Reanimate: Subtype %s not unlocked at spell level %d." % [subtype_names.get(selected_subtype, "Unknown"), spell_level])
		return -1 # Indicate subtype not available / not unlocked

	var cost = subtype_base_de_costs.get(selected_subtype, 999)
	# Future enhancement: cost -= (spell_level - subtype_unlock_level.get(selected_subtype, 1))
	return cost


# spell_specific_arg here is the selected_subtype (enum value)
func cast(caster_node, target_data = null, selected_subtype = null) -> bool:
	if selected_subtype == null: selected_subtype = ReanimateSubtype.SKELETON # Default
	if not selected_subtype is ReanimateSubtype:
		printerr("Reanimate cast: Invalid selected_subtype type.")
		if is_instance_valid(caster_node) and caster_node.has_signal("spell_cast_failed"):
			caster_node.emit_signal("spell_cast_failed", spell_name, "Internal error: Invalid subtype.")
		return false

	if not is_instance_valid(caster) or not is_instance_valid(game_manager):
		printerr("Reanimate '%s': Caster or GameManager reference not set." % spell_name)
		if is_instance_valid(caster_node) and caster_node.has_signal("spell_cast_failed"):
			caster_node.emit_signal("spell_cast_failed", spell_name, "Internal Error: Caster/GM missing.")
		return false
	
	if not can_cast(caster_node, caster.current_de, target_data, selected_subtype):
		return false # can_cast emits specific failure

	var current_de_cost_for_subtype = get_current_de_cost(selected_subtype)
	if not caster.spend_de(current_de_cost_for_subtype): 
		printerr("Reanimate '%s': Failed to spend %d DE (unexpected)." % [spell_name, current_de_cost_for_subtype]) 
		if is_instance_valid(caster_node) and caster_node.has_signal("spell_cast_failed"):
			caster_node.emit_signal("spell_cast_failed", spell_name, "Failed to spend DE.")
		return false

	var success = apply_effect(caster_node, target_data, selected_subtype)
	
	if not success:
		if is_instance_valid(caster_node) and caster_node.has_signal("spell_cast_failed"):
			caster_node.emit_signal("spell_cast_failed", spell_name, "Failed to apply reanimation effect for %s." % subtype_names.get(selected_subtype, "Unknown"))
	return success

# spell_specific_arg here is the selected_subtype (enum value)
func apply_effect(_caster_node, target_data = null, selected_subtype = null) -> bool:
	if selected_subtype == null: selected_subtype = ReanimateSubtype.SKELETON
	if not selected_subtype is ReanimateSubtype:
		printerr("Reanimate apply_effect: Invalid selected_subtype type.")
		return false

	var corpse: CorpseData = target_data
	if not is_instance_valid(corpse): 
		printerr("Reanimate '%s' apply_effect: Invalid corpse data." % spell_name)
		return false

	var new_undead_finality: int = corpse.finality_counter - 1 
	if new_undead_finality < 0: 
		printerr("Reanimate '%s' apply_effect: Calculated new Undead finality < 0." % spell_name)
		return false

	var creature_config = {}
	var creature_script_path = ""
	var creature_base_name = ""

	match selected_subtype:
		ReanimateSubtype.SKELETON:
			creature_script_path = "res://scripts/creatures/Skeleton.gd"
			creature_base_name = "Skeleton"
			creature_config = { "max_health": 1, "attack_power": 1, "speed_type": Creature.SpeedType.NORMAL, "is_flying": false, "has_reach": false }
		ReanimateSubtype.ZOMBIE:
			creature_script_path = "res://scripts/creatures/Zombie.gd"
			creature_base_name = "Zombie"
			creature_config = { "max_health": corpse.original_max_health, "attack_power": 1, "speed_type": Creature.SpeedType.SLOW, "is_flying": false, "has_reach": corpse.original_had_reach }
		ReanimateSubtype.SPIRIT:
			creature_script_path = "res://scripts/creatures/Spirit.gd"
			creature_base_name = "Spirit"
			creature_config = { "max_health": 1, "attack_power": corpse.original_attack_power, "speed_type": Creature.SpeedType.FAST, "is_flying": true, "has_reach": false }
		_:
			printerr("Reanimate '%s': Unknown selected subtype %s." % [spell_name, selected_subtype])
			return false
	
	creature_config["creature_class_script_path"] = creature_script_path
	creature_config["creature_name"] = "%s of %s" % [creature_base_name, corpse.original_creature_name] if selected_subtype != ReanimateSubtype.SKELETON else creature_base_name
	creature_config["finality_counter"] = new_undead_finality
	
	if not is_instance_valid(game_manager):
		printerr("Reanimate '%s' apply_effect: GameManager reference is not valid." % spell_name)
		return false
	
	var spawn_pos: Vector2i = corpse.grid_pos_on_death
	if not battle_grid.is_valid_grid_position(spawn_pos):
		var player_back_row_y = battle_grid.get_player_row_y_by_faction_row_num(1)
		if player_back_row_y != -1:
			spawn_pos = battle_grid.find_first_empty_cell_in_row(player_back_row_y)
		if not battle_grid.is_valid_grid_position(spawn_pos): 
			printerr("Reanimate '%s' apply_effect: Could not find a valid fallback spawn position." % spell_name)
			return false

	var new_undead_node = game_manager.spawn_reanimated_creature(creature_config, spawn_pos)

	if is_instance_valid(new_undead_node):
		game_manager.consume_corpse(corpse) 
		return true
	else:
		printerr("Reanimate '%s' apply_effect: GameManager failed to spawn creature at %s." % [spell_name, str(spawn_pos)])
		return false

# --- OVERRIDE OTHER OPTIONAL METHODS ---

# spell_specific_arg here is the selected_subtype (enum value)
func can_cast(caster_node, current_de_on_caster: int, target_data = null, selected_subtype = null) -> bool:
	if selected_subtype == null: selected_subtype = ReanimateSubtype.SKELETON
	if not selected_subtype is ReanimateSubtype:
		printerr("Reanimate can_cast: Invalid selected_subtype type.")
		if is_instance_valid(caster_node) and caster_node.has_signal("spell_cast_failed"):
			caster_node.emit_signal("spell_cast_failed", spell_name, "Internal error: Invalid subtype for can_cast.")
		return false

	# Check subtype unlock level first
	if spell_level < subtype_unlock_level.get(selected_subtype, 99):
		if is_instance_valid(caster_node) and caster_node.has_signal("spell_cast_failed"):
			caster_node.emit_signal("spell_cast_failed", spell_name, "%s not unlocked (Req. Spell L%d)." % [subtype_names.get(selected_subtype, "Type"), subtype_unlock_level.get(selected_subtype, 99)])
		return false

	# Now call super.can_cast, which will use get_current_de_cost(selected_subtype)
	if not super.can_cast(caster_node, current_de_on_caster, target_data, selected_subtype): 
		return false # Super should have emitted specific failure (e.g. DE)

	# Corpse-specific checks
	if not target_data is CorpseData:
		if is_instance_valid(caster_node) and caster_node.has_signal("spell_cast_failed"):
			caster_node.emit_signal("spell_cast_failed", spell_name, "Invalid target. Expected CorpseData.")
		return false

	var corpse: CorpseData = target_data
	if not corpse.can_be_reanimated():
		if is_instance_valid(caster_node) and caster_node.has_signal("spell_cast_failed"):
			caster_node.emit_signal("spell_cast_failed", spell_name, "Corpse cannot be reanimated (Finality: %d)." % corpse.finality_counter)
		return false
	
	# Check spawn location validity
	var spawn_pos_ok = battle_grid.is_valid_grid_position(corpse.grid_pos_on_death)
	if not spawn_pos_ok:
		var player_back_row_y = battle_grid.get_player_row_y_by_faction_row_num(1)
		var fallback_pos = Vector2i(-1,-1)
		if player_back_row_y != -1:
			fallback_pos = battle_grid.find_first_empty_cell_in_row(player_back_row_y)
		if not battle_grid.is_valid_grid_position(fallback_pos):
			if is_instance_valid(caster_node) and caster_node.has_signal("spell_cast_failed"):
				caster_node.emit_signal("spell_cast_failed", spell_name, "No valid spawn location for reanimation.")
			return false
			
	return true

func get_valid_targets(_caster_node, _all_creatures: Array, _all_corpses: Array) -> Array[CorpseData]:
	var valid_targets: Array[CorpseData] = []
	if not is_instance_valid(game_manager):
		printerr("Reanimate '%s' get_valid_targets: GameManager reference not set." % spell_name)
		return valid_targets
	for corpse_resource in game_manager.get_available_corpses(): 
		if corpse_resource is CorpseData and corpse_resource.can_be_reanimated():
			valid_targets.append(corpse_resource)
	return valid_targets

# spell_specific_arg here is the selected_subtype (enum value)
func get_level_specific_description(selected_subtype = null) -> String:
	if selected_subtype == null: selected_subtype = ReanimateSubtype.SKELETON
	if not selected_subtype is ReanimateSubtype: return "Invalid subtype selected."

	var type_name = subtype_names.get(selected_subtype, "Unknown Type")
	var unlock_lvl = subtype_unlock_level.get(selected_subtype, 99)
	var desc = "Raises a %s from a corpse." % type_name.to_lower()
	if spell_level < unlock_lvl :
		desc += " (Unlocks at Reanimate Spell L%d)" % unlock_lvl
	else:
		desc += " (Unlocked)"
	desc += "\nConsumes 1 Finality from the corpse."
	return desc

func upgrade_spell() -> bool: # Upgrading the Reanimate spell itself
	if super.upgrade_spell(): 
		# print_debug("Reanimate '%s' spell upgraded to L%d." % [spell_name, spell_level])
		# This might unlock new subtypes or make existing ones cheaper (future enhancement)
		return true
	return false

func get_subtype_name_from_enum(subtype_enum_val: ReanimateSubtype) -> String:
	return subtype_names.get(subtype_enum_val, "Unknown")

func get_subtype_enum_from_index(index: int) -> ReanimateSubtype:
	match index:
		0: return ReanimateSubtype.SKELETON
		1: return ReanimateSubtype.ZOMBIE
		2: return ReanimateSubtype.SPIRIT
		_: return ReanimateSubtype.SKELETON # Default
