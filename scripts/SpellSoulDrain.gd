extends Spell

class_name SpellSoulDrain

func _init():
	cost_by_level = [2, 3, 4, 5]

func do_effect(caster, target = null) -> void:
	print("💀 Soul Drain (Lv %d) effect!" % level)
