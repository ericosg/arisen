# ./scripts/spells/SpellData.gd
extends Resource # Still a Resource to be passed around, but data defined in .gd
class_name SpellData

# This is a base class for spell data and logic.
# Specific spells will inherit from this and define their own data.

# --- COMMON VARIABLES (Values to be set by child classes in their _init) ---
var spell_name: String = "Unnamed Spell"
var spell_description: String = "No description."
var required_mc_level: int = 1 # Minimum Necromancer level to use this spell
var spell_level: int = 1 # Current level of this spell instance, starts at 1
var max_spell_level: int = 1 # To be calculated by child: mastery_costs.size() + 1

# Array storing the MP cost to upgrade TO level 2, level 3, etc.
# Populated by child spell scripts.
var mastery_costs: Array[int] = []

# Target type enum
enum TargetType { NONE, SELF, ALLY_CREATURE, ENEMY_CREATURE, CORPSE, GRID_CELL, ALL_ALLIES, ALL_ENEMIES }
var target_type: TargetType = TargetType.NONE

# --- RUNTIME REFERENCES (Set by Necromancer) ---
var caster # The Necromancer instance casting the spell
var game_manager # Reference to the GameManager for accessing game state
var battle_grid # Reference to the BattleGrid if needed for targeting

# _init() in the base class can be minimal.
# Child classes will do the heavy lifting of setting their specific properties.
func _init():
	spell_level = 1 # Ensure spells always start at level 1

# --- METHODS TO BE IMPLEMENTED/OVERRIDDEN BY CHILD CLASSES ---

# Child classes MUST implement this to return their current DE cost.
func get_current_de_cost() -> int:
	printerr("Spell '%s': get_current_de_cost() not implemented by child class!" % spell_name)
	return 999 # Return a high value to likely prevent casting

# Child classes MUST implement the actual spell effect.
func apply_effect(caster_node, target_data = null):
	printerr("Spell '%s' apply_effect() method not implemented by child class!" % spell_name)
	pass

# Child classes MUST implement the main spell casting logic.
func cast(caster_node, target_data = null) -> bool:
	printerr("Spell '%s' cast() method not implemented by child class!" % spell_name)
	if is_instance_valid(caster_node) and caster_node.has_signal("spell_cast_failed"):
		caster_node.emit_signal("spell_cast_failed", spell_name, "Cast logic not implemented.")
	return false

# Child classes can override to provide specific descriptions based on their level.
func get_level_specific_description() -> String:
	return spell_description

# Child classes can override for specific targeting logic.
func get_valid_targets(_caster_node, _all_creatures: Array, _all_corpses: Array) -> Array:
	# print_debug("Spell '%s' get_valid_targets() not implemented by child. Returning empty array." % spell_name)
	return []

# --- COMMON METHODS ---

# Base can_cast checks common conditions.
# Child classes can call super.can_cast() and add their own specific checks.
func can_cast(caster_node, current_de_on_caster: int, _target_data = null) -> bool:
	if not is_instance_valid(caster_node):
		printerr("Spell '%s': Caster node is invalid." % spell_name)
		return false
	
	if caster_node.level < required_mc_level:
		if is_instance_valid(caster_node) and caster_node.has_signal("spell_cast_failed"):
			caster_node.emit_signal("spell_cast_failed", spell_name, "Requires Necromancer Lvl %d" % required_mc_level)
		# print_debug("Spell '%s' requires Necromancer level %d. Caster level: %d" % [spell_name, required_mc_level, caster_node.level])
		return false
	
	var current_spell_de_cost = get_current_de_cost()
	if current_de_on_caster < current_spell_de_cost:
		if is_instance_valid(caster_node) and caster_node.has_signal("spell_cast_failed"):
			caster_node.emit_signal("spell_cast_failed", spell_name, "Not enough DE (needs %d)" % current_spell_de_cost)
		# print_debug("Spell '%s' cannot be cast. Not enough DE. Has: %d, Needs: %d" % [spell_name, current_de_on_caster, current_spell_de_cost])
		return false
	
	return true

# Base upgrade_spell method just increments the level.
# Child classes' overridden version will call this super method.
# No DE cost update needed here as get_current_de_cost() handles it.
func upgrade_spell() -> bool:
	if spell_level < max_spell_level:
		spell_level += 1
		# print_debug("Spell '%s' base upgraded to level %d." % [spell_name, spell_level])
		return true
	# print_debug("Spell '%s' is already at max level (%d)." % [spell_name, max_spell_level])
	return false

# Helper to set runtime references. Called by Necromancer when spells are learned/assigned.
func set_runtime_references(caster_node, gm_node, bg_node):
	self.caster = caster_node
	self.game_manager = gm_node
	self.battle_grid = bg_node

# Method to get the mastery point cost for the next upgrade.
func get_mastery_cost_for_next_upgrade() -> int:
	if spell_level >= max_spell_level:
		return -1 # Already at max level or no more defined costs

	# mastery_costs stores cost to upgrade TO L2, L3, ...
	# Index is (target_level - 2) or (current_spell_level - 1)
	var cost_index = spell_level - 1 

	if cost_index >= 0 and cost_index < mastery_costs.size():
		return mastery_costs[cost_index]
	
	# print_debug("Spell '%s': No mastery cost defined for upgrading from level %d to %d." % [spell_name, spell_level, spell_level + 1])
	return -1 # Cost not defined or error

# Common UI helper
func get_description_with_level_and_cost() -> String:
	return "%s (L%d)\nDE Cost: %d\n%s" % [spell_name, spell_level, get_current_de_cost(), get_level_specific_description()]
