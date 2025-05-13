# SpellReanimate.gd
extends Spell
class_name SpellReanimate

enum ReanimateSubType { # More specific than just "Type"
	SKELETON = 0,
	ZOMBIE = 1,
	SPIRIT = 2
}

var current_reanimate_subtype: ReanimateSubType = ReanimateSubType.SKELETON

# Button to toggle reanimation type (assigned from Necromancer)
var assigned_type_button: Button = null 

func _init() -> void: # Set costs for Reanimate spell specifically
	# Cost to upgrade Reanimate TO level: L2, L3, L4, L5
	mastery_cost_per_level = [2, 3, 4, 5] # Cost to upgrade to L2, L3, L4, L5
	# DE cost to cast Reanimate AT level: L1, L2, L3, L4, L5
	de_cost_per_level = [2, 2, 3, 3, 4] # Base cost, might adjust with subtype
	update_de_cost_based_on_subtype()

func assign_type_button(button_node: Button):
	if is_instance_valid(button_node):
		assigned_type_button = button_node
		assigned_type_button.connect("pressed", Callable(self, "_on_cycle_reanimate_subtype"))
		update_type_button_text_if_assigned()
	else:
		push_warning("SpellReanimate: Attempted to assign an invalid type button.")


func update_de_cost_based_on_subtype() -> void:
	# Base DE costs are for Skeletons
	var base_costs_at_level = [2, 2, 3, 3, 4] # L1 to L5
	
	# Adjust costs based on current level and subtype
	var current_level_idx = clamp(level - 1, 0, base_costs_at_level.size() - 1)
	var base_cost_for_current_level = base_costs_at_level[current_level_idx]

	# Apply multipliers or additions for Zombie/Spirit
	# This is a simple override; a more complex system could modify the de_cost_per_level array
	var final_de_cost = base_cost_for_current_level
	match current_reanimate_subtype:
		ReanimateSubType.SKELETON:
			pass # Uses base cost
		ReanimateSubType.ZOMBIE:
			final_de_cost += 1 # Zombies cost +1 DE example
		ReanimateSubType.SPIRIT:
			final_de_cost += 2 # Spirits cost +2 DE example
	
	# This is a slight hack: get_de_cost() reads from array.
	# For dynamic costs like this, get_de_cost() in this class should calculate it.
	# Let's override get_de_cost here:
	# No, easier to just adjust the de_cost_per_level array when subtype changes.
	# For now, let Spell.get_de_cost use the array. The subtype will modify this array.
	# This is tricky. Simpler: get_de_cost in SpellReanimate overrides and calculates.

	# Override Spell.get_de_cost() for dynamic calculation:
	# (See overridden get_de_cost function below)
	pass # Actual cost calculation will be in the overridden get_de_cost()


func get_de_cost() -> int: # Override from Spell.gd
	if level - 1 < de_cost_per_level.size() and level > 0:
		var base_cost = de_cost_per_level[level-1] # Base cost for current level (Skeleton)
		match current_reanimate_subtype:
			ReanimateSubType.ZOMBIE:
				return base_cost + 1 # Example: Zombies always cost 1 more than Skeleton at same spell level
			ReanimateSubType.SPIRIT:
				return base_cost + 2 # Example: Spirits always cost 2 more
			_: # SKELETON or default
				return base_cost
	return 999 # Should not happen


func set_reanimate_subtype(new_subtype: ReanimateSubType) -> void:
	current_reanimate_subtype = new_subtype
	update_de_cost_based_on_subtype() # Recalculate costs or update UI if needed
	update_type_button_text_if_assigned()
	print("Reanimate subtype changed to: ", get_subtype_name())

func _on_cycle_reanimate_subtype() -> void:
	current_reanimate_subtype = (current_reanimate_subtype + 1) % 3 # Cycle through 0, 1, 2
	set_reanimate_subtype(current_reanimate_subtype)
	# The Necromancer's UI update will reflect the new cost if it calls get_de_cost()

func update_type_button_text_if_assigned() -> void:
	if is_instance_valid(assigned_type_button):
		assigned_type_button.text = "Type: %s" % get_subtype_name()

func get_subtype_name() -> String:
	match current_reanimate_subtype:
		ReanimateSubType.SKELETON: return "Skeleton"
		ReanimateSubType.ZOMBIE: return "Zombie"
		ReanimateSubType.SPIRIT: return "Spirit"
		_: return "Unknown"


# target_data here is the dead_creature_info dictionary from GameManager/Necromancer
func do_effect(caster: Node, target_data = null) -> void:
	if target_data == null or not target_data is Dictionary:
		push_error("Reanimate spell: Invalid or missing target data for reanimation.")
		# Potentially refund DE to caster if spell fails early
		if caster.has_method("_update_ui"): caster._update_ui() # Refresh UI if DE was consumed
		return

	var game_manager = $GameManager
	if not game_manager or not game_manager.has_method("reanimate_creature_from_data"):
		push_error("Reanimate spell: GameManager not found or method missing.")
		return

	var necromancer_level = 1
	if caster.has_meta("level"): # Assuming Necromancer node has 'level' property
		necromancer_level = caster.level
	elif caster.get("level") != null : # Common way to store level
		necromancer_level = caster.get("level")


	print("Casting Reanimate (L%d, Type: %s) on data: %s" % [level, get_subtype_name(), target_data])
	
	game_manager.reanimate_creature_from_data(
		target_data,                  # The dead_creature_info dictionary
		get_subtype_name().to_lower(),# "skeleton", "zombie", or "spirit"
		necromancer_level
	)
	# DE was already deducted by Necromancer before calling do_effect.
	# Necromancer's _update_ui will be called after this.
