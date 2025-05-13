# SpellReanimate.gd
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
	
	# Update costs based on type
	match current_type:
		ReanimateType.SKELETON:
			# Base costs, no change
			pass
		ReanimateType.ZOMBIE:
			# Zombies cost more
			de_cost_by_level = [3, 3, 4, 4, 6]
		ReanimateType.SPIRIT:
			# Spirits cost most
			de_cost_by_level = [4, 4, 5, 5, 7]

func do_effect(caster, target = null) -> void:
	print("🔮 Reanimate (Lv %d) effect!" % level)
	
	var game_manager = get_node_or_null("/root/GameManager")
	if not game_manager:
		push_error("GameManager not found")
		return
		
	var battle_grid = game_manager.battle_grid
	if not battle_grid:
		push_error("BattleGrid not found")
		return
	
	# If no target specified, use player's cursor position
	var grid_pos: Vector2
	if target is Vector2:
		# Target is already a grid position
		grid_pos = target
	else:
		# Convert mouse position to grid position
		var mouse_pos = caster.get_viewport().get_mouse_position()
		grid_pos = battle_grid.world_to_grid(mouse_pos)
	
	var undead_type = ""
	match current_type:
		ReanimateType.SKELETON:
			undead_type = "skeleton"
		ReanimateType.ZOMBIE:
			undead_type = "zombie"
		ReanimateType.SPIRIT:
			undead_type = "spirit"
	
	game_manager.reanimate_at_position(grid_pos, undead_type, caster.level)

# Add a toggle button for the UI
@onready var type_button: Button = null

func _ready() -> void:
	# Find the type toggle button if it exists
	type_button = get_node_or_null("/root/MainScene/UI/ReanimateTypeButton")
	if type_button:
		type_button.connect("pressed", Callable(self, "on_type_button_pressed"))
		update_type_button()

func get_type_name() -> String:
	match current_type:
		ReanimateType.SKELETON:
			return "Skeleton"
		ReanimateType.ZOMBIE:
			return "Zombie"
		ReanimateType.SPIRIT:
			return "Spirit"
		_:
			return "Unknown"

func cycle_type() -> void:
	current_type = (current_type + 1) % 3
	set_type(current_type)

func on_type_button_pressed() -> void:
	cycle_type()
	update_type_button()

func update_type_button() -> void:
	var type_button = get_node_or_null("/root/MainScene/UI/ReanimateTypeButton")
	if type_button:
		type_button.text = "Type: %s" % get_type_name()
