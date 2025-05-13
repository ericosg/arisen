# SpellReanimate.gd
extends Spell

class_name SpellReanimate

func _init():
	mastery_cost_by_level = [2, 2, 3, 3, 5]
	de_cost_by_level = [2, 2, 3, 3, 5]

func do_effect(caster, target = null) -> void:
	print("🔮 Reanimate (Lv %d) effect!" % level)
