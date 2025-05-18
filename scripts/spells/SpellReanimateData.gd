# ./scripts/spells/SpellReanimateData.gd
extends SpellData
class_name SpellReanimateData

# --- UNDEAD TYPE MAPPING ---
const UNDEAD_TYPE_SKELETON = "Skeleton"
const UNDEAD_TYPE_ZOMBIE = "Zombie"
const UNDEAD_TYPE_SPIRIT = "Spirit"

# --- SPELL-SPECIFIC DATA ---
var de_costs_per_level: Array[int] # DE cost FOR CASTING AT L1, L2, L3

func _init():
	super._init() # Call base class _init if it does anything

	# --- Define all specific properties for Reanimate ---
	spell_name = "Reanimate"
	spell_description = "Raises a fallen creature as an Undead servant. Type depends on spell level."
	required_mc_level = 1
	target_type = TargetType.CORPSE # From SpellData.TargetType enum

	# Define DE costs for casting AT each level (L1, L2, L3)
	de_costs_per_level = [10, 12, 15] 

	# Define Mastery Point costs to upgrade TO L2, then TO L3
	mastery_costs = [2, 3] 

	# Calculate max_spell_level based on mastery_costs array
	# If mastery_costs = [cost_to_L2, cost_to_L3], then size is 2, max_level is 2+1=3
	max_spell_level = mastery_costs.size() + 1
	
	# spell_level is already initialized to 1 by SpellData's _init()

# --- OVERRIDE REQUIRED METHODS ---

func get_current_de_cost() -> int:
	if spell_level - 1 >= 0 and spell_level - 1 < de_costs_per_level.size():
		return de_costs_per_level[spell_level - 1]
	else:
		printerr("Reanimate '%s': Invalid spell_level %d for de_costs_per_level (size %d)." % [spell_name, spell_level, de_costs_per_level.size()])
		return 999 # Fallback high cost

func cast(caster_node, target_data = null) -> bool:
	if not is_instance_valid(caster) or not is_instance_valid(game_manager): # Check inherited caster/gm
		printerr("Reanimate '%s': Caster or GameManager reference not set." % spell_name)
		if is_instance_valid(caster_node) and caster_node.has_signal("spell_cast_failed"):
			caster_node.emit_signal("spell_cast_failed", spell_name, "Internal Error: Caster/GM missing.")
		return false
	
	if not can_cast(caster_node, caster.current_de, target_data): # can_cast uses get_current_de_cost()
		# can_cast itself should emit "spell_cast_failed" with a reason
		return false

	if not caster.spend_de(get_current_de_cost()): 
		printerr("Reanimate '%s': Failed to spend DE (unexpected after can_cast)." % spell_name) 
		if is_instance_valid(caster_node) and caster_node.has_signal("spell_cast_failed"):
			caster_node.emit_signal("spell_cast_failed", spell_name, "Failed to spend DE.")
		return false

	var success = apply_effect(caster_node, target_data)
	
	if not success:
		if is_instance_valid(caster_node) and caster_node.has_signal("spell_cast_failed"):
			caster_node.emit_signal("spell_cast_failed", spell_name, "Failed to apply reanimation effect.")
		# print_debug("Reanimate '%s' failed to apply effect." % spell_name)
	#else:
		# print_debug("Reanimate '%s' cast successfully." % spell_name)
		
	return success

func apply_effect(_caster_node, target_data = null) -> bool:
	var corpse: CorpseData = target_data
	if not is_instance_valid(corpse): 
		printerr("Reanimate '%s' apply_effect: Invalid corpse data." % spell_name)
		return false

	var undead_type_to_create: String = get_undead_type_for_current_level()
	var new_undead_finality: int = corpse.finality_counter - 1 

	if new_undead_finality < 0: # Should be caught by corpse.can_be_reanimated in can_cast
		printerr("Reanimate '%s' apply_effect: Calculated new Undead finality < 0." % spell_name)
		return false

	var creature_config = {} 
	match undead_type_to_create:
		UNDEAD_TYPE_SKELETON:
			creature_config = {
				"creature_class_script_path": "res://scripts/creatures/Skeleton.gd",
				"creature_name": "Skeleton", "max_health": 1, "attack_power": 1,
				"speed_type": Creature.SpeedType.NORMAL, "is_flying": false, "has_reach": false,
				"finality_counter": new_undead_finality
			}
		UNDEAD_TYPE_ZOMBIE:
			creature_config = {
				"creature_class_script_path": "res://scripts/creatures/Zombie.gd",
				"creature_name": "Zombie (%s)" % corpse.original_creature_name,
				"max_health": corpse.original_max_health, "attack_power": 1,
				"speed_type": Creature.SpeedType.SLOW, "is_flying": false, "has_reach": corpse.original_had_reach,
				"finality_counter": new_undead_finality
			}
		UNDEAD_TYPE_SPIRIT:
			creature_config = {
				"creature_class_script_path": "res://scripts/creatures/Spirit.gd",
				"creature_name": "Spirit of %s" % corpse.original_creature_name,
				"max_health": 1, "attack_power": corpse.original_attack_power,
				"speed_type": Creature.SpeedType.FAST, "is_flying": true, "has_reach": false,
				"finality_counter": new_undead_finality
			}
		_:
			printerr("Reanimate '%s': Unknown Undead type '%s' for spell level %d." % [spell_name, undead_type_to_create, spell_level])
			return false
	
	if not is_instance_valid(game_manager):
		printerr("Reanimate '%s' apply_effect: GameManager reference is not valid." % spell_name)
		return false
		
	var new_undead_node = game_manager.spawn_reanimated_creature(creature_config)

	if is_instance_valid(new_undead_node):
		game_manager.consume_corpse(corpse) 
		return true
	else:
		printerr("Reanimate '%s' apply_effect: GameManager failed to spawn creature." % spell_name)
		return false

# --- OVERRIDE OTHER OPTIONAL METHODS ---

# Override can_cast to add Reanimate-specific target checks
func can_cast(caster_node, current_de_on_caster: int, target_data = null) -> bool:
	if not super.can_cast(caster_node, current_de_on_caster, target_data): # Base checks (MC level, DE)
		return false

	if not target_data is CorpseData:
		if is_instance_valid(caster_node) and caster_node.has_signal("spell_cast_failed"):
			caster_node.emit_signal("spell_cast_failed", spell_name, "Invalid target. Expected CorpseData.")
		# else: printerr("Reanimate '%s' can_cast: Invalid target. Expected CorpseData." % spell_name)
		return false

	var corpse: CorpseData = target_data
	if not corpse.can_be_reanimated():
		if is_instance_valid(caster_node) and caster_node.has_signal("spell_cast_failed"):
			caster_node.emit_signal("spell_cast_failed", spell_name, "Corpse cannot be reanimated (Finality: %d)." % corpse.finality_counter)
		# else: print_debug("Reanimate '%s' can_cast: Corpse (Finality: %d) cannot be reanimated." % [spell_name, corpse.finality_counter])
		return false
	
	var undead_type_to_create = get_undead_type_for_current_level()
	if undead_type_to_create == "":
		if is_instance_valid(caster_node) and caster_node.has_signal("spell_cast_failed"):
			caster_node.emit_signal("spell_cast_failed", spell_name, "No valid Undead type for spell level %d." % spell_level)
		# else: printerr("Reanimate '%s' can_cast: No valid Undead type for spell level %d." % [spell_name, spell_level])
		return false

	return true

func get_undead_type_for_current_level() -> String:
	match spell_level:
		1: return UNDEAD_TYPE_SKELETON
		2: return UNDEAD_TYPE_ZOMBIE
		3: return UNDEAD_TYPE_SPIRIT
		_: return "" 

func get_valid_targets(_caster_node, _all_creatures: Array, _all_corpses: Array) -> Array[CorpseData]:
	var valid_targets: Array[CorpseData] = []
	if not is_instance_valid(game_manager):
		printerr("Reanimate '%s' get_valid_targets: GameManager reference not set." % spell_name)
		return valid_targets

	for corpse_resource in game_manager.get_available_corpses(): 
		if corpse_resource is CorpseData and corpse_resource.can_be_reanimated():
			valid_targets.append(corpse_resource)
	return valid_targets

func get_level_specific_description() -> String:
	var undead_type = get_undead_type_for_current_level()
	if undead_type == "":
		return "Raises a fallen creature as an Undead. (Invalid spell level for type selection)"
	return "Raises a %s from a corpse.\nConsumes 1 Finality from the corpse." % undead_type.to_lower()

# Override upgrade_spell to update current de_cost from its array
func upgrade_spell() -> bool:
	if super.upgrade_spell(): # This increments spell_level in SpellData
		# The current DE cost is now fetched by get_current_de_cost(),
		# so no need to update a singular de_cost variable here.
		# print_debug("Reanimate '%s' upgraded to L%d. DE cost: %d. Summons: %s" % [spell_name, spell_level, get_current_de_cost(), get_undead_type_for_current_level()])
		return true
	return false
