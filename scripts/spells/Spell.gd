# Spell.gd
extends Node
class_name Spell

enum SpellType {
	REANIMATE,
	SOUL_DRAIN,
	# Add more spell types here
}

@export var level: int = 1
@export var max_level: int = 5 # Example max spell level

# Costs should be defined per level
# Example: mastery_cost_per_level[0] is cost for level 1, mastery_cost_per_level[1] for level 2, etc.
@export var mastery_cost_per_level: Array[int] = [1, 2, 3, 4, 5] # Cost to upgrade TO this level from previous
@export var de_cost_per_level: Array[int] = [2, 3, 4, 5, 6]    # DE cost to cast AT this level

func get_mastery_cost() -> int: # Cost to upgrade to (level + 1)
	if level >= max_level:
		return -1 # Cannot upgrade further (or a very high number)
	if level < mastery_cost_per_level.size(): # مستوى 0 للترقية إلى 1، مستوى 1 إلى 2، إلخ.
		return mastery_cost_per_level[level] # Cost to reach (current_level + 1)
	return -1 # Default if not defined (shouldn't happen with proper array setup)

func get_de_cost() -> int: # Cost to cast at current level
	if level - 1 < de_cost_per_level.size() and level > 0:
		return de_cost_per_level[level-1]
	return 999 # Default if not defined

func level_up() -> bool:
	if level < max_level:
		level += 1
		print("%s leveled up to %d" % [self.get_class(), level])
		# Potentially emit a signal or update spell effects based on new level
		return true
	print("%s is already at max level %d" % [self.get_class(), max_level])
	return false

# Base effect function to be overridden by specific spells
# caster: The Node that cast the spell (e.g., Necromancer instance)
# target_data: Can be anything the spell needs - Vector2 for position, a Creature instance, etc.
# For Reanimate, target_data will be the dead_creature_info dictionary.
# For Soul Drain, target_data might be a Creature instance or null for AoE.
func do_effect(caster: Node, target_data = null) -> void:
	push_error("do_effect() not implemented in spell: %s" % get_class())
