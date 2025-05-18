# ./scripts/creatures/Creature.gd
extends Node2D
class_name Creature

# Signals
signal died(creature_instance: Creature)
signal health_changed(creature_instance: Creature, new_health: int, max_health: int)
signal grid_position_changed(creature_instance: Creature, new_grid_pos: Vector2i)

# --- ENUMS ---
enum Faction { NONE, HUMAN, ALIEN, UNDEAD }
enum SpeedType { SLOW, NORMAL, FAST }

# --- CORE ATTRIBUTES ---
@export var creature_name: String = "Creature"
@export var max_health: int = 10 : set = _set_max_health
@export var current_health: int = 10 : set = _set_current_health
@export var attack_power: int = 1

@export var faction: Faction = Faction.NONE
@export var speed_type: SpeedType = SpeedType.NORMAL

@export var is_flying: bool = false
@export var has_reach: bool = false

# --- STATE ---
var is_alive: bool = true
var is_targetable: bool = true
var grid_pos: Vector2i = Vector2i(-1, -1) : set = _set_grid_pos

var reanimation_payload_data: Dictionary = {
	"original_creature_name": "", "original_max_health": 0, "original_attack_power": 0,
	"original_was_flying": false, "original_had_reach": false, "original_faction": Faction.NONE
}
# Finality counter is primarily for Undead, but defined here for broader access if needed.
# For non-Undead, it will typically remain 0 or unused.
@export var finality_counter: int = 0 : set = _set_finality_counter


# --- NODE REFERENCES ---
var game_manager: GameManager
var battle_grid: BattleGrid

@onready var sprite_node_ref: Sprite2D = $Sprite

# --- UI ELEMENTS ---
# Configuration for UI elements
const UI_FONT_SIZE: int = 12
const UI_PADDING: int = 1
const UI_ICON_SIZE: int = 16

# Preload font (ensure this path is correct)
const PIXEL_FONT_BOLD: Font = preload("res://assets/fonts/PixelOperator8-Bold.ttf")

# UI Node References
var stats_label: Label
var level_label: Label
var ability_icons_container: HBoxContainer
var finality_label: Label # Though primarily for Undead, declare here for potential base class use

# Placeholder textures for ability icons
var icon_texture_flying: Texture2D = load("res://assets/images/icon_flying.png")
var icon_texture_reach: Texture2D = load("res://assets/images/icon_reach.png")
var icon_texture_speed_slow: Texture2D = load("res://assets/images/icon_speed_slow.png")
var icon_texture_speed_normal: Texture2D = load("res://assets/images/icon_speed_normal.png")
var icon_texture_speed_fast: Texture2D = load("res://assets/images/icon_speed_fast.png")


func _ready():
	_set_current_health(min(current_health, max_health)) # Ensure health is clamped on ready
	_update_reanimation_payload_from_current_stats()

	if not is_instance_valid(sprite_node_ref):
		printerr("Creature '%s' _ready(): Child Sprite2D node named 'Sprite' STILL not found by @onready var." % creature_name)

	# Setup UI elements after the creature itself is ready
	_setup_ui_elements()
	_update_all_ui_elements() # Initial update of all UI

	# Connect signals for UI updates
	health_changed.connect(_on_health_changed_ui_update)
	# If attack_power can change dynamically, add a signal and connect it too.
	# For now, we assume attack_power is set on init.

func _setup_ui_elements():
	# --- Stats Label (Attack/Health) ---
	stats_label = Label.new()
	stats_label.name = "StatsLabel"
	stats_label.set_horizontal_alignment(HORIZONTAL_ALIGNMENT_RIGHT)
	stats_label.set_vertical_alignment(VERTICAL_ALIGNMENT_BOTTOM)
	# Font settings
	var stats_font_settings = FontVariation.new()
	stats_font_settings.set_base_font(PIXEL_FONT_BOLD)
	stats_font_settings.set_variation_opentype({"size": UI_FONT_SIZE})
	stats_label.add_theme_font_override("font", stats_font_settings)
	stats_label.add_theme_font_size_override("font_size", UI_FONT_SIZE) # Explicitly set size
	stats_label.modulate = Color.WHITE # Default color
	add_child(stats_label)
	# Position: Bottom-right of the 64x64 tile.
	# Creature origin is center of 64x64 cell. So cell half-width/height is CELL_SIZE / 2.0
	var cell_half_size = BattleGrid.CELL_SIZE / 2.0
	stats_label.position = Vector2(cell_half_size - UI_PADDING, cell_half_size - UI_PADDING)
	# Since the label is aligned bottom-right, its position is its bottom-right corner.

	# --- Level Label ---
	level_label = Label.new()
	level_label.name = "LevelLabel"
	level_label.set_horizontal_alignment(HORIZONTAL_ALIGNMENT_LEFT)
	level_label.set_vertical_alignment(VERTICAL_ALIGNMENT_TOP)
	# Font settings
	var level_font_settings = FontVariation.new()
	level_font_settings.set_base_font(PIXEL_FONT_BOLD)
	level_font_settings.set_variation_opentype({"size": UI_FONT_SIZE})
	level_label.add_theme_font_override("font", level_font_settings)
	level_label.add_theme_font_size_override("font_size", UI_FONT_SIZE)
	level_label.modulate = Color.WHITE
	add_child(level_label)
	# Position: Top-left of the 64x64 tile.
	level_label.position = Vector2(-cell_half_size + UI_PADDING, -cell_half_size + UI_PADDING)
	# Since the label is aligned top-left, its position is its top-left corner.

	# --- Ability Icons Container ---
	ability_icons_container = HBoxContainer.new()
	ability_icons_container.name = "AbilityIconsContainer"
	# Alignment within HBoxContainer items (though with fixed size icons, may not be critical)
	ability_icons_container.set_alignment(BoxContainer.ALIGNMENT_END) # Aligns icons to the right of the container
	add_child(ability_icons_container)
	# Position: Top-right of the 64x64 tile.
	# The container's top-right corner should be at (cell_half_size - UI_PADDING, -cell_half_size + UI_PADDING)
	# We'll position individual icons within it. The HBoxContainer itself will be positioned.
	# The position of HBoxContainer is its top-left corner.
	# To align its content to the top-right of the cell:
	# Set its position so its top-right would be at (cell_half_size - UI_PADDING, -cell_half_size + UI_PADDING)
	# This needs to account for the container's width. We'll adjust after adding icons.
	# For now, let's set a placeholder position and refine it in _update_ability_icons
	ability_icons_container.position = Vector2(cell_half_size - (3 * UI_ICON_SIZE) - UI_PADDING, -cell_half_size + UI_PADDING) # Rough estimate

	# --- Finality Label (for Undead, setup here for structure) ---
	# This will be primarily managed and made visible by Undead.gd
	finality_label = Label.new()
	finality_label.name = "FinalityLabel"
	finality_label.set_horizontal_alignment(HORIZONTAL_ALIGNMENT_LEFT)
	finality_label.set_vertical_alignment(VERTICAL_ALIGNMENT_BOTTOM)
	var finality_font_settings = FontVariation.new()
	finality_font_settings.set_base_font(PIXEL_FONT_BOLD)
	finality_font_settings.set_variation_opentype({"size": UI_FONT_SIZE})
	finality_label.add_theme_font_override("font", finality_font_settings)
	finality_label.add_theme_font_size_override("font_size", UI_FONT_SIZE)
	finality_label.modulate = Color.WHITE
	finality_label.visible = false # Hidden by default for non-Undead
	add_child(finality_label)
	# Position: Bottom-left of the 64x64 tile.
	finality_label.position = Vector2(-cell_half_size + UI_PADDING, cell_half_size - UI_PADDING)


func _update_reanimation_payload_from_current_stats():
	reanimation_payload_data["original_creature_name"] = creature_name
	reanimation_payload_data["original_max_health"] = max_health
	reanimation_payload_data["original_attack_power"] = attack_power
	reanimation_payload_data["original_was_flying"] = is_flying
	reanimation_payload_data["original_had_reach"] = has_reach
	reanimation_payload_data["original_faction"] = faction

# --- SETTERS ---
func _set_max_health(value: int):
	max_health = max(1, value)
	if current_health > max_health: _set_current_health(max_health) # This will trigger health_changed
	else: emit_signal("health_changed", self, current_health, max_health) # Ensure signal emits if current_health didn't change

func _set_current_health(value: int):
	var old_health = current_health
	current_health = clamp(value, 0, max_health)
	if old_health != current_health:
		emit_signal("health_changed", self, current_health, max_health)
		if current_health <= 0 and is_alive: die()

func _set_grid_pos(new_pos: Vector2i):
	if grid_pos != new_pos:
		grid_pos = new_pos
		if is_instance_valid(battle_grid) and battle_grid.is_valid_grid_position(grid_pos): # Check validity before getting world pos
			self.position = battle_grid.get_world_position_for_grid_cell_center(grid_pos)
		elif new_pos != Vector2i(-1,-1) and not is_instance_valid(battle_grid):
			printerr("Creature '%s': BattleGrid ref missing. Cannot update visual pos for %s." % [creature_name, str(new_pos)])
		emit_signal("grid_position_changed", self, new_pos)

func _set_finality_counter(value: int):
	var old_finality = finality_counter
	finality_counter = max(0, value)
	if old_finality != finality_counter:
		# This signal is more relevant for Undead, but emit if changed.
		# Undead.gd will connect to this or have its own specific signal.
		if faction == Faction.UNDEAD and has_signal("finality_changed"): # Check if Undead.gd added this signal
			emit_signal("finality_changed", self, finality_counter)
		_update_finality_label_ui() # Update UI if it's visible


# --- CORE METHODS ---
func initialize_creature(config: Dictionary):
	creature_name = config.get("creature_name", "Default Name")
	# Max health must be set before current health to ensure correct clamping
	_set_max_health(config.get("max_health", 10)) # Use setter to trigger signals
	_set_current_health(max_health) # Initialize to full health, use setter

	attack_power = config.get("attack_power", 1)
	faction = config.get("faction", Faction.NONE)
	speed_type = config.get("speed_type", SpeedType.NORMAL)
	is_flying = config.get("is_flying", false)
	has_reach = config.get("has_reach", false)

	if config.has("finality_counter"): # For Undead primarily
		_set_finality_counter(config.get("finality_counter", 0))

	_update_reanimation_payload_from_current_stats()
	is_alive = true
	is_targetable = true

	var local_sprite_node: Sprite2D = get_node_or_null("Sprite") as Sprite2D
	if is_instance_valid(local_sprite_node):
		var texture_path = config.get("sprite_texture_path", "res://icon.svg")
		if ResourceLoader.exists(texture_path):
			var loaded_texture: Texture2D = load(texture_path)
			if is_instance_valid(loaded_texture):
				local_sprite_node.texture = loaded_texture
				var texture_size = loaded_texture.get_size()
				if texture_size.x > 0 and texture_size.y > 0 and is_instance_valid(battle_grid):
					var cell_s = float(BattleGrid.CELL_SIZE)
					var scale_x = cell_s / texture_size.x
					var scale_y = cell_s / texture_size.y
					var final_scale = min(scale_x, scale_y)
					local_sprite_node.scale = Vector2(final_scale, final_scale)
				elif not is_instance_valid(battle_grid):
					printerr("Creature '%s': BattleGrid reference missing, cannot calculate scale for sprite." % creature_name)
			else:
				printerr("Creature '%s': Loaded resource at '%s' is NOT a valid Texture2D. Using default." % [creature_name, texture_path])
				local_sprite_node.texture = load("res://icon.svg")
		else:
			printerr("Creature '%s': Texture path NOT FOUND: '%s'. Using default icon." % [creature_name, texture_path])
			local_sprite_node.texture = load("res://icon.svg")
	else:
		printerr("Creature '%s': CRITICAL - Sprite node (child 'Sprite') MISSING in initialize_creature." % creature_name)
	
	# Update UI elements after initialization
	_update_all_ui_elements()


func take_damage(amount: int):
	if not is_alive or amount <= 0: return
	_set_current_health(current_health - amount) # Use setter

func die():
	if not is_alive: return
	is_alive = false; is_targetable = false
	# Optionally hide UI elements on death
	if is_instance_valid(stats_label): stats_label.visible = false
	if is_instance_valid(level_label): level_label.visible = false
	if is_instance_valid(ability_icons_container): ability_icons_container.visible = false
	if is_instance_valid(finality_label): finality_label.visible = false
	emit_signal("died", self)

func can_attack_target(target_creature: Creature) -> bool:
	if not is_instance_valid(target_creature) or not target_creature.is_alive or not target_creature.is_targetable: return false
	if not self.is_alive: return false
	if target_creature.faction == self.faction and self.faction != Faction.NONE: return false # No friendly fire
	# Flying/Reach interaction:
	# If target is flying AND self is not flying AND self does not have reach, then cannot attack.
	if target_creature.is_flying and not self.is_flying and not self.has_reach: return false
	return true

func get_tooltip_info() -> Dictionary:
	return {
		"name": creature_name, "health": "%d/%d" % [current_health, max_health], "attack": attack_power,
		"speed": SpeedType.keys()[speed_type].to_lower(), "is_flying": is_flying, "has_reach": has_reach,
		"faction": Faction.keys()[faction],
		"finality": finality_counter if faction == Faction.UNDEAD else "N/A"
	}

func get_data_for_corpse_creation() -> Dictionary:
	var corpse_data = reanimation_payload_data.duplicate(true) # Start with base data
	# If this creature is Undead, its current finality counter at death is important.
	if self.faction == Faction.UNDEAD:
		corpse_data["current_finality_counter_on_death"] = self.finality_counter
	return corpse_data

# --- UI UPDATE FUNCTIONS ---
func _on_health_changed_ui_update(_creature, _new_health, _max_health):
	_update_stats_label_ui()

func _update_all_ui_elements():
	_update_stats_label_ui()
	_update_level_label_ui()
	_update_ability_icons_ui()
	_update_finality_label_ui() # Called here, but visibility is handled by Undead.gd

func _update_stats_label_ui():
	if not is_instance_valid(stats_label): return
	stats_label.text = "%d/%d" % [attack_power, current_health]
	if current_health < max_health:
		stats_label.modulate = Color.RED # Damaged health in red
	else:
		stats_label.modulate = Color.WHITE # Full health in white

func _update_level_label_ui():
	if not is_instance_valid(level_label): return
	# Creature level isn't implemented yet, so default to "Lvl 1"
	level_label.text = "Lvl 1" # Placeholder

func _update_ability_icons_ui():
	if not is_instance_valid(ability_icons_container): return

	# Clear existing icons
	for child in ability_icons_container.get_children():
		child.queue_free()

	var cell_half_size = BattleGrid.CELL_SIZE / 2.0
	var current_x_offset = 0 # For manual positioning if HBox doesn't size as expected initially

	# Speed Icon
	var speed_icon_node = TextureRect.new()
	speed_icon_node.custom_minimum_size = Vector2(UI_ICON_SIZE, UI_ICON_SIZE)
	match speed_type:
		SpeedType.SLOW:
			speed_icon_node.texture = icon_texture_speed_slow
		SpeedType.NORMAL:
			speed_icon_node.texture = icon_texture_speed_normal
		SpeedType.FAST:
			speed_icon_node.texture = icon_texture_speed_fast
	ability_icons_container.add_child(speed_icon_node)
	current_x_offset += UI_ICON_SIZE + ability_icons_container.get_theme_constant("separation", "HBoxContainer")


	# Flying Icon
	if is_flying:
		var flying_icon_node = TextureRect.new()
		flying_icon_node.texture = icon_texture_flying
		flying_icon_node.custom_minimum_size = Vector2(UI_ICON_SIZE, UI_ICON_SIZE)
		ability_icons_container.add_child(flying_icon_node)
		current_x_offset += UI_ICON_SIZE + ability_icons_container.get_theme_constant("separation", "HBoxContainer")

	# Reach Icon
	if has_reach:
		var reach_icon_node = TextureRect.new()
		reach_icon_node.texture = icon_texture_reach
		reach_icon_node.custom_minimum_size = Vector2(UI_ICON_SIZE, UI_ICON_SIZE)
		ability_icons_container.add_child(reach_icon_node)
		current_x_offset += UI_ICON_SIZE # Last icon, no separation after it needed for width calc

	# Position the container: Top-Right
	# The container's position is its top-left. We want its top-right to be at the cell's top-right with padding.
	# So, new_x = (cell_half_size - UI_PADDING) - container_width
	# We need to wait for the HBoxContainer to arrange its children to get its actual width.
	# A call_deferred might be needed if size isn't updated immediately.
	# For now, we'll use the calculated current_x_offset as an approximation of width.
	# If HBoxContainer has internal padding, this might need adjustment.
	var container_width = current_x_offset
	if ability_icons_container.get_child_count() > 0 : # Remove last separation if any
		container_width -= ability_icons_container.get_theme_constant("separation", "HBoxContainer")
	
	ability_icons_container.position = Vector2(
		cell_half_size - container_width - UI_PADDING,
		-cell_half_size + UI_PADDING
	)
	ability_icons_container.visible = ability_icons_container.get_child_count() > 0


func _update_finality_label_ui():
	if not is_instance_valid(finality_label): return
	# This will be primarily controlled by Undead.gd, which sets visibility
	if finality_label.visible: # Only update text if it's meant to be seen
		finality_label.text = str(finality_counter)
