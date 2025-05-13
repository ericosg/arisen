# SpellReanimate.gd - Updated version
extends Spell
class_name SpellReanimate

enum ReanimateType {
	SKELETON = 0,
	ZOMBIE = 1,
	SPIRIT = 2
}

var current_type: int = ReanimateType.SKELETON

func _init():
	mastery_cost_by_level = [2, 2, 3, 3, 5]
	de_cost_by_level = [2, 2, 3, 3, 5]

func set_type(new_type: int) -> void:
	current_type = new_type

func do_effect(caster, target = null) -> void:
	print("🔮 Reanimate (Lv %d) effect!" % level)
	
	# Use the helper class to perform the actual reanimation
	ReanimateEffect.perform_reanimation(caster, target, current_type)
