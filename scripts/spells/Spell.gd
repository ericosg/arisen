# Spell.gd
extends Node
class_name Spell

enum SpellType {
	REANIMATE,
	SOUL_DRAIN,
}

var level: int = 1
var mastery_cost_by_level: Array[int] = []
var de_cost_by_level: Array[int] = []

func get_mastery_cost() -> int:
	var idx = clamp(level - 1, 0, mastery_cost_by_level.size() - 1)
	return mastery_cost_by_level[idx]

func get_de_cost() -> int:
	var idx = clamp(level - 1, 0, de_cost_by_level.size() - 1)
	return de_cost_by_level[idx]

func level_up() -> void:
	level += 1

# override in subclasses
func do_effect(caster, target = null) -> void:
	push_error("do_effect() not implemented in %s" % get_class())
