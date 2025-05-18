# ./scripts/spells/SpellData.gd
extends Resource 
class_name SpellData

# This is a base class for spell data and logic.
# Specific spells will inherit from this and define their own data.

# --- COMMON VARIABLES (Values to be set by child classes in their _init) ---
var spell_name: String = "Unnamed Spell"
var spell_description: String = "No description."
var required_mc_level: int = 1 
var spell_level: int = 1 
var max_spell_level: int = 1 

var mastery_costs: Array[int] = [] # MP cost to upgrade TO L2, L3, etc.

enum TargetType { NONE, SELF, ALLY_CREATURE, ENEMY_CREATURE, CORPSE, GRID_CELL, ALL_ALLIES, ALL_ENEMIES }
var target_type: TargetType = TargetType.NONE

# --- RUNTIME REFERENCES (Set by Necromancer) ---
var caster 
var game_manager 
var battle_grid 

func _init():
	spell_level = 1 

# --- METHODS TO BE IMPLEMENTED/OVERRIDDEN BY CHILD CLASSES ---

# Child classes MUST implement this to return their current DE cost.
# spell_specific_arg can be used for spells like Reanimate that have subtypes.
func get_current_de_cost(spell_specific_arg = null) -> int:
	printerr("Spell '%s': get_current_de_cost() not implemented by child class!" % spell_name)
	return 999 

func apply_effect(caster_node, target_data = null, spell_specific_arg = null):
	printerr("Spell '%s' apply_effect() method not implemented by child class!" % spell_name)
	pass

func cast(caster_node, target_data = null, spell_specific_arg = null) -> bool:
	printerr("Spell '%s' cast() method not implemented by child class!" % spell_name)
	if is_instance_valid(caster_node) and caster_node.has_signal("spell_cast_failed"):
		caster_node.emit_signal("spell_cast_failed", spell_name, "Cast logic not implemented.")
	return false

func get_level_specific_description(spell_specific_arg = null) -> String: # Added arg for consistency
	return spell_description

func get_valid_targets(_caster_node, _all_creatures: Array, _all_corpses: Array) -> Array:
	return []

# --- COMMON METHODS ---

func can_cast(caster_node, current_de_on_caster: int, target_data = null, spell_specific_arg = null) -> bool:
	if not is_instance_valid(caster_node):
		printerr("Spell '%s': Caster node is invalid." % spell_name)
		return false
	
	if caster_node.level < required_mc_level:
		if is_instance_valid(caster_node) and caster_node.has_signal("spell_cast_failed"):
			caster_node.emit_signal("spell_cast_failed", spell_name, "Requires Necromancer Lvl %d" % required_mc_level)
		return false
	
	var current_spell_de_cost = get_current_de_cost(spell_specific_arg)
	if current_spell_de_cost == -1 : # Indicates subtype not available or error
		# get_current_de_cost in child should emit specific failure if appropriate
		# For Reanimate, it will check unlock level.
		# This is a general catch.
		if is_instance_valid(caster_node) and caster_node.has_signal("spell_cast_failed"):
			caster_node.emit_signal("spell_cast_failed", spell_name, "Selected type/option not available at current spell level.")
		return false

	if current_de_on_caster < current_spell_de_cost:
		if is_instance_valid(caster_node) and caster_node.has_signal("spell_cast_failed"):
			caster_node.emit_signal("spell_cast_failed", spell_name, "Not enough DE (needs %d)" % current_spell_de_cost)
		return false
	
	return true

func upgrade_spell() -> bool:
	if spell_level < max_spell_level:
		spell_level += 1
		return true
	return false

func set_runtime_references(caster_node, gm_node, bg_node):
	self.caster = caster_node
	self.game_manager = gm_node
	self.battle_grid = bg_node

func get_mastery_cost_for_next_upgrade() -> int:
	if spell_level >= max_spell_level:
		return -1 
	var cost_index = spell_level - 1 
	if cost_index >= 0 and cost_index < mastery_costs.size():
		return mastery_costs[cost_index]
	return -1 

func get_description_with_level_and_cost(spell_specific_arg = null) -> String:
	return "%s (L%d)\nDE Cost: %d\n%s" % [spell_name, spell_level, get_current_de_cost(spell_specific_arg), get_level_specific_description(spell_specific_arg)]
