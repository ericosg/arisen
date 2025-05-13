# SpellSoulDrain.gd
extends Spell
class_name SpellSoulDrain

func _init() -> void:
	# Cost to upgrade Soul Drain TO level: L2, L3, L4, L5
	mastery_cost_per_level = [1, 2, 3, 4]
	# DE cost to cast Soul Drain AT level: L1, L2, L3, L4, L5
	de_cost_per_level = [1, 2, 3, 4, 5]

# target can be a specific Creature instance or null for an area/random effect
func do_effect(caster: Node, target_creature_instance = null) -> void:
	print("Casting Soul Drain (Level %d)" % level)

	var game_manager = $GameManager
	if not game_manager:
		push_error("SoulDrain: GameManager not found!")
		return

	var damage_amount = level * 2 + 1 # Example: L1=3, L2=5, L3=7
	var de_restored = level * 1 + 1 # Example: L1=2, L2=3, L3=4

	var targets_hit = 0

	if is_instance_valid(target_creature_instance) and target_creature_instance is Creature:
		# Single target Soul Drain
		if not target_creature_instance.is_dead() and \
		   (target_creature_instance.faction == Creature.CreatureFaction.ALIEN or \
			target_creature_instance.faction == Creature.CreatureFaction.HUMAN): # Cannot drain Undead
			
			print("Soul Drain hits %s for %d damage." % [target_creature_instance.name, damage_amount])
			target_creature_instance.take_damage(damage_amount)
			targets_hit = 1
	else:
		# AoE Soul Drain: Hit a few random enemies or all in an area
		# Example: Hit up to 'level' number of random valid (non-undead) enemies
		var potential_targets = []
		for creature in game_manager.living_aliens + game_manager.living_humans: # Combine lists
			if is_instance_valid(creature) and not creature.is_dead():
				potential_targets.append(creature)
		
		potential_targets.shuffle()
		
		var num_to_hit = min(potential_targets.size(), level) # Hit up to 'level' targets
		for i in range(num_to_hit):
			var random_target: Creature = potential_targets[i]
			print("Soul Drain (AoE) hits %s for %d damage." % [random_target.name, damage_amount])
			random_target.take_damage(damage_amount)
			targets_hit += 1
	
	if targets_hit > 0:
		var actual_de_restored = de_restored * targets_hit
		if caster.has_method("get") and caster.has_method("set") and caster.has_method("_update_ui"):
			var caster_current_de = caster.get("current_de")
			var caster_max_de = caster.get("max_de")
			caster.set("current_de", min(caster_max_de, caster_current_de + actual_de_restored))
			caster._update_ui() # Make sure Necromancer has _update_ui
			print("Soul Drain restored %d DE to Necromancer." % actual_de_restored)
	else:
		print("Soul Drain found no valid targets.")

	# DE was already deducted by Necromancer. Update UI handled by Necromancer.
