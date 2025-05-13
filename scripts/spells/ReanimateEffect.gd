# ReanimateEffect.gd
# This is a utility class to handle the actual reanimation logic 
# for your existing SpellReanimate class
class_name ReanimateEffect
extends Node

enum ReanimateType {
	SKELETON = 0,
	ZOMBIE = 1,
	SPIRIT = 2
}

# Use this function in your SpellReanimate's do_effect method
static func perform_reanimation(caster, target = null, type: int = ReanimateType.SKELETON) -> void:
	var game_manager = caster.get_node("/root/GameManager")
	if not game_manager:
		push_error("GameManager not found")
		return
	
	# If no target specified, use player's cursor position
	var position
	if target:
		position = target
	else:
		# This is just placeholder logic - you'll need to implement 
		# the actual conversion from mouse position to grid coordinates
		var mouse_pos = caster.get_viewport().get_mouse_position()
		position = Vector2(
			int(mouse_pos.x / 64),  # Assuming 64px grid
			int(mouse_pos.y / 64)
		)
	
	var undead_type = ""
	match type:
		ReanimateType.SKELETON:
			undead_type = "skeleton"
		ReanimateType.ZOMBIE:
			undead_type = "zombie"
		ReanimateType.SPIRIT:
			undead_type = "spirit"
	
	game_manager.reanimate_at_position(position, undead_type)
