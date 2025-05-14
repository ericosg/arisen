# ./scripts/spells/Spell.gd
extends Resource # Spells can be Resources holding data and logic
class_name SpellData

# This is a base class for spell data and logic.
# Specific spells will inherit from this.

@export var spell_name: String = "Generic Spell"
@export var spell_description: String = "Casts a generic spell effect."
@export var de_cost: int = 5
@export var required_mc_level: int = 1 # Minimum Necromancer level to use this spell
@export var spell_level: int = 1 # Current level of this spell instance (can be upgraded)
@export var max_spell_level: int = 5 # Max level this spell can be upgraded to

# Target type enum - might be useful for UI or validation
enum TargetType { NONE, SELF, ALLY_CREATURE, ENEMY_CREATURE, CORPSE, GRID_CELL, ALL_ALLIES, ALL_ENEMIES }
@export var target_type: TargetType = TargetType.NONE

# --- References (to be set when the spell is prepared or cast) ---
# These are not part of the Resource's saved state but are needed at runtime.
var caster # The Necromancer instance casting the spell
var game_manager # Reference to the GameManager for accessing game state
var battle_grid # Reference to the BattleGrid if needed for targeting

func _init(config: Dictionary = {}):
	if not config.is_empty():
		spell_name = config.get("spell_name", spell_name)
		spell_description = config.get("spell_description", spell_description)
		de_cost = config.get("de_cost", de_cost)
		required_mc_level = config.get("required_mc_level", required_mc_level)
		spell_level = config.get("spell_level", spell_level)
		max_spell_level = config.get("max_spell_level", max_spell_level)
		target_type = config.get("target_type", target_type)

# Called by the Necromancer to check if the spell can be cast.
# Specific spells might override this to add more conditions.
func can_cast(caster_node, current_de: int) -> bool:
	if not is_instance_valid(caster_node):
		printerr("Spell: Caster node is invalid.")
		return false
	# Assuming Necromancer has a 'level' property
	# if caster_node.has_method("get_level") and caster_node.get_level() < required_mc_level:
	# printerr("Spell '%s' requires MC level %d. Caster level: %d" % [spell_name, required_mc_level, caster_node.get_level()])
	# return false
	
	if current_de < de_cost:
		# print_debug("Spell '%s' cannot be cast. Not enough DE. Has: %d, Needs: %d" % [spell_name, current_de, de_cost])
		return false
	
	return true

# Placeholder for the main spell casting logic.
# Specific spells MUST override this method.
# `target_data` can be anything: a Creature node, a CorpseData resource, a Vector2i for grid cell, etc.
func cast(caster_node, target_data = null) -> bool:
	printerr("Spell '%s' cast() method not implemented!" % spell_name)
	# Basic structure:
	# 1. Perform final checks.
	# 2. Apply DE cost to caster.
	# 3. Execute spell effect.
	# 4. Return true if successful, false otherwise.
	return false

# Placeholder for spell effect logic. Often called by cast().
# Specific spells will implement their unique effects here.
func apply_effect(caster_node, target_data = null):
	printerr("Spell '%s' apply_effect() method not implemented!" % spell_name)
	pass

# Placeholder for getting targeting information or validating targets.
# Specific spells can override this.
func get_valid_targets(caster_node, all_creatures: Array, all_corpses: Array) -> Array:
	# print_debug("Spell '%s' get_valid_targets() not implemented. Returning empty array." % spell_name)
	return []

func get_description_with_level() -> String:
	return "%s (Lvl %d)\nDE Cost: %d\n%s" % [spell_name, spell_level, de_cost, get_level_specific_description()]

# Specific spells should override this to show what changes with levels.
func get_level_specific_description() -> String:
	return spell_description # Base description by default

func upgrade_spell():
	if spell_level < max_spell_level:
		spell_level += 1
		# Specific spells should override this to update their stats based on the new level
		# (e.g., increased damage, reduced DE cost, more targets).
		# print_debug("Spell '%s' upgraded to level %d." % [spell_name, spell_level])
		return true
	# print_debug("Spell '%s' is already at max level (%d)." % [spell_name, max_spell_level])
	return false

# Helper to set runtime references. Called by Necromancer when preparing spells.
func set_runtime_references(caster_node, gm_node, bg_node):
	self.caster = caster_node
	self.game_manager = gm_node
	self.battle_grid = bg_node
