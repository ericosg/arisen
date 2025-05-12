extends Node

class_name Spell

enum SpellType {
	REANIMATE,
	SOUL_DRAIN,
}

@export var cost_by_level: Array[int] = []
var level: int = 1

func get_cost() -> int:
	var idx = clamp(level - 1, 0, cost_by_level.size() - 1)
	return cost_by_level[idx]

func level_up() -> void:
	level += 1

# override in subclasses
func do_effect(caster, target = null) -> void:
	push_error("do_effect() not implemented in %s" % get_class())
