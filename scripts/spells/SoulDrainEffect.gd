# SoulDrainEffect.gd
# This is a utility class to handle the actual soul drain logic
# for your existing SpellSoulDrain class
class_name SoulDrainEffect
extends Node

# Use this function in your SpellSoulDrain's do_effect method
static func perform_soul_drain(caster, target = null, drain_level: int = 1) -> void:
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
	
	# Find creatures at position
	var creatures = game_manager.get_creatures_at_position(position)
	
	# Soul drain only works on aliens and humans, not undead
	var valid_targets = []
	for creature in creatures:
		if creature is Alien or creature is Human:
			valid_targets.append(creature)
	
	if valid_targets.size() == 0:
		print("No valid targets for Soul Drain")
		return
	
	# Get the first valid target
	var target_creature = valid_targets[0]
	
	# Calculate drain amount based on spell level
	var drain_amount = drain_level * 2
	
	# Damage the target
	target_creature.take_damage(drain_amount)
	print("💀 Soul Drain dealt %d damage to %s" % [drain_amount, target_creature.get_class()])
	
	# Restore DE to caster
	var de_restore = drain_level * 3
	caster.current_de = min(caster.current_de + de_restore, caster.max_de)
	caster.update_ui()
	print("💀 Soul Drain restored %d DE" % de_restore)
