# SpellSoulDrain.gd
extends Spell

class_name SpellSoulDrain

func _init():
	mastery_cost_by_level = [1, 3, 5, 10]
	de_cost_by_level = [1, 3, 5, 10]

func do_effect(caster, target = null) -> void:
	print("💀 Soul Drain (Lv %d) effect!" % level)
