extends Spell

class_name SpellReanimate

func _init():
	cost_by_level = [1, 1, 2, 3, 5]

func do_effect(caster, target = null) -> void:
	print("🔮 Reanimate (Lv %d) effect!" % level)
