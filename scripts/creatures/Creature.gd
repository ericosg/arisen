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
@export var level: int = 1 : set = _set_level # ADDED: Creature level
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
	"original_creature_name": "", "original_level": 1, "original_max_health": 0, "original_attack_power": 0, # ADDED original_level
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
const UI_PADDING: int = 1 # Padding from the edges of the creature's cell
const UI_ICON_SIZE: int = 16 # Assumes icons are square

# Preload font (ensure this path is correct)
const PIXEL_FONT_BOLD: Font = preload("res://assets/fonts/PixelOperator8-Bold.ttf")

# UI Node References
var stats_label: Label
var level_label: Label # MODIFIED: Will now display actual level
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
	# If attack_power or level can change dynamically post-init, add signals and connect them too.


func _setup_ui_elements():
	var cell_half_size = BattleGrid.CELL_SIZE / 2.0 # Assuming BattleGrid.CELL_SIZE is accessible or defined

	# --- Stats Label (Attack/Health) ---
	stats_label = Label.new()
	stats_label.name = "StatsLabel"
	stats_label.set_vertical_alignment(VERTICAL_ALIGNMENT_BOTTOM) 
	var stats_font_settings = FontVariation.new()
	stats_font_settings.set_base_font(PIXEL_FONT_BOLD)
	stats_font_settings.set_variation_opentype({"size": UI_FONT_SIZE})
	stats_label.add_theme_font_override("font", stats_font_settings)
	stats_label.add_theme_font_size_override("font_size", UI_FONT_SIZE)
	stats_label.modulate = Color.WHITE
	add_child(stats_label)

	# --- Level Label ---
	level_label = Label.new()
	level_label.name = "LevelLabel"
	level_label.set_horizontal_alignment(HORIZONTAL_ALIGNMENT_LEFT)
	level_label.set_vertical_alignment(VERTICAL_ALIGNMENT_TOP)
	var level_font_settings = FontVariation.new() 
	level_font_settings.set_base_font(PIXEL_FONT_BOLD)
	level_font_settings.set_variation_opentype({"size": UI_FONT_SIZE})
	level_label.add_theme_font_override("font", level_font_settings)
	level_label.add_theme_font_size_override("font_size", UI_FONT_SIZE)
	level_label.modulate = Color.WHITE
	add_child(level_label)
	level_label.position = Vector2(-cell_half_size + UI_PADDING, -cell_half_size + UI_PADDING)

	# --- Ability Icons Container ---
	ability_icons_container = HBoxContainer.new()
	ability_icons_container.name = "AbilityIconsContainer"
	ability_icons_container.set_alignment(BoxContainer.ALIGNMENT_END)
	add_child(ability_icons_container)

	# --- Finality Label (for Undead) ---
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
	finality_label.visible = false 
	add_child(finality_label)
	finality_label.position = Vector2(-cell_half_size + UI_PADDING, cell_half_size - UI_PADDING - finality_label.get_minimum_size().y)


func _update_reanimation_payload_from_current_stats():
	reanimation_payload_data["original_creature_name"] = creature_name
	reanimation_payload_data["original_level"] = level # ADDED: Store original level
	reanimation_payload_data["original_max_health"] = max_health
	reanimation_payload_data["original_attack_power"] = attack_power
	reanimation_payload_data["original_was_flying"] = is_flying
	reanimation_payload_data["original_had_reach"] = has_reach
	reanimation_payload_data["original_faction"] = faction

# --- SETTERS ---
func _set_level(value: int): # ADDED: Setter for level
	var old_level = level
	level = max(1, value)
	if old_level != level:
		_update_level_label_ui() # Update UI if level changes
		_update_reanimation_payload_from_current_stats() # Ensure payload is up-to-date

func _set_max_health(value: int):
	max_health = max(1, value)
	if current_health > max_health: _set_current_health(max_health)
	else: emit_signal("health_changed", self, current_health, max_health)
	_update_reanimation_payload_from_current_stats()


func _set_current_health(value: int):
	var old_health = current_health
	current_health = clamp(value, 0, max_health)
	if old_health != current_health:
		emit_signal("health_changed", self, current_health, max_health)
		if current_health <= 0 and is_alive: die()

func _set_grid_pos(new_pos: Vector2i):
	if grid_pos != new_pos:
		grid_pos = new_pos
		if is_instance_valid(battle_grid) and battle_grid.is_valid_grid_position(grid_pos):
			self.position = battle_grid.get_world_position_for_grid_cell_center(grid_pos)
		elif new_pos != Vector2i(-1,-1) and not is_instance_valid(battle_grid):
			printerr("Creature '%s': BattleGrid ref missing. Cannot update visual pos for %s." % [creature_name, str(new_pos)])
		emit_signal("grid_position_changed", self, new_pos)

func _set_finality_counter(value: int):
	var old_finality = finality_counter
	finality_counter = max(0, value)
	if old_finality != finality_counter:
		if faction == Faction.UNDEAD and has_signal("finality_changed"): # Assuming Undead.gd might add this signal
			emit_signal("finality_changed", self, finality_counter)
		_update_finality_label_ui()


# --- CORE METHODS ---
func initialize_creature(config: Dictionary):
	creature_name = config.get("creature_name", "Default Name")
	_set_level(config.get("level", 1)) # MODIFIED: Initialize level from config
	_set_max_health(config.get("max_health", 10))
	_set_current_health(max_health) # current_health should be set after max_health

	attack_power = config.get("attack_power", 1)
	faction = config.get("faction", Faction.NONE)
	speed_type = config.get("speed_type", SpeedType.NORMAL)
	is_flying = config.get("is_flying", false)
	has_reach = config.get("has_reach", false)

	if config.has("finality_counter"):
		_set_finality_counter(config.get("finality_counter", 0))

	_update_reanimation_payload_from_current_stats() # Call after all attributes are set
	is_alive = true
	is_targetable = true

	var local_sprite_node: Sprite2D = get_node_or_null("Sprite") as Sprite2D
	if is_instance_valid(local_sprite_node):
		var texture_path = config.get("sprite_texture_path", "res://icon.svg")
		if ResourceLoader.exists(texture_path):
			var loaded_texture: Texture2D = load(texture_path)
			if is_instance_valid(loaded_texture):
				local_sprite_node.texture = loaded_texture
				local_sprite_node.scale = Vector2(1,1) 
			else:
				printerr("Creature '%s': Loaded resource at '%s' is NOT a valid Texture2D." % [creature_name, texture_path])
				local_sprite_node.texture = load("res://icon.svg") # Fallback
		else:
			printerr("Creature '%s': Texture path NOT FOUND: '%s'." % [creature_name, texture_path])
			local_sprite_node.texture = load("res://icon.svg") # Fallback
	else:
		printerr("Creature '%s': CRITICAL - Sprite node (child 'Sprite') MISSING." % creature_name)
	
	_update_all_ui_elements() # Ensure UI reflects initial state


func take_damage(amount: int):
	if not is_alive or amount <= 0: return
	_set_current_health(current_health - amount)

func die():
	if not is_alive: return
	is_alive = false; is_targetable = false
	# Hide UI elements on death
	if is_instance_valid(stats_label): stats_label.visible = false
	if is_instance_valid(level_label): level_label.visible = false
	if is_instance_valid(ability_icons_container): ability_icons_container.visible = false
	if is_instance_valid(finality_label): finality_label.visible = false
	emit_signal("died", self)

func can_attack_target(target_creature: Creature) -> bool:
	if not is_instance_valid(target_creature) or not target_creature.is_alive or not target_creature.is_targetable: return false
	if not self.is_alive: return false
	# Prevent attacking same faction, unless faction is NONE (e.g. neutral entities if any)
	if target_creature.faction == self.faction and self.faction != Faction.NONE: return false
	# Handle flying vs non-flying/reach
	if target_creature.is_flying and not self.is_flying and not self.has_reach: return false
	return true

func get_tooltip_info() -> Dictionary:
	return {
		"name": creature_name, "level": level, "health": "%d/%d" % [current_health, max_health], "attack": attack_power, # ADDED level
		"speed": SpeedType.keys()[speed_type].to_lower(), "is_flying": is_flying, "has_reach": has_reach,
		"faction": Faction.keys()[faction],
		"finality": finality_counter if faction == Faction.UNDEAD else "N/A"
	}

func get_data_for_corpse_creation() -> Dictionary:
	# Ensure the payload is up-to-date before returning
	_update_reanimation_payload_from_current_stats()
	var corpse_data = reanimation_payload_data.duplicate(true)
	# If this creature is Undead, its current finality is passed along.
	# This is handled in Undead.gd or when GameManager creates CorpseData.
	# For now, ensure the base payload is correct.
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
	_update_finality_label_ui()

func _update_stats_label_ui():
	if not is_instance_valid(stats_label): return
	stats_label.text = "%d/%d" % [attack_power, current_health] # AP / CurrentHP
	if current_health < max_health: # Simple visual cue for damage
		stats_label.modulate = Color.ORANGE_RED # More distinct than just RED
	else:
		stats_label.modulate = Color.WHITE

	stats_label.set_horizontal_alignment(HORIZONTAL_ALIGNMENT_RIGHT)
	var min_size = stats_label.get_minimum_size()
	stats_label.size = min_size 

	var label_size = stats_label.size 
	var cell_half_size = BattleGrid.CELL_SIZE / 2.0

	stats_label.position = Vector2(
		(cell_half_size - UI_PADDING) - label_size.x,  
		(cell_half_size - UI_PADDING) - label_size.y   
	)

func _update_level_label_ui(): # MODIFIED: Update to show actual level
	if not is_instance_valid(level_label): return
	level_label.text = "L%d" % level # Display current level

func _update_ability_icons_ui():
	if not is_instance_valid(ability_icons_container): return

	for child in ability_icons_container.get_children():
		child.queue_free()

	var cell_half_size = BattleGrid.CELL_SIZE / 2.0
	var number_of_icons = 0

	var speed_icon_node = TextureRect.new()
	speed_icon_node.custom_minimum_size = Vector2(UI_ICON_SIZE, UI_ICON_SIZE)
	speed_icon_node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	speed_icon_node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	match speed_type:
		SpeedType.SLOW: speed_icon_node.texture = icon_texture_speed_slow
		SpeedType.NORMAL: speed_icon_node.texture = icon_texture_speed_normal
		SpeedType.FAST: speed_icon_node.texture = icon_texture_speed_fast
	ability_icons_container.add_child(speed_icon_node)
	number_of_icons += 1

	if is_flying:
		var flying_icon_node = TextureRect.new()
		flying_icon_node.texture = icon_texture_flying
		flying_icon_node.custom_minimum_size = Vector2(UI_ICON_SIZE, UI_ICON_SIZE)
		flying_icon_node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		flying_icon_node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ability_icons_container.add_child(flying_icon_node)
		number_of_icons += 1

	if has_reach:
		var reach_icon_node = TextureRect.new()
		reach_icon_node.texture = icon_texture_reach
		reach_icon_node.custom_minimum_size = Vector2(UI_ICON_SIZE, UI_ICON_SIZE)
		reach_icon_node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		reach_icon_node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ability_icons_container.add_child(reach_icon_node)
		number_of_icons += 1

	if number_of_icons == 0:
		ability_icons_container.visible = false
		return
	else:
		ability_icons_container.visible = true

	var separation = ability_icons_container.get_theme_constant("separation", "HBoxContainer")
	var container_width = (number_of_icons * UI_ICON_SIZE)
	if number_of_icons > 1: 
		container_width += (number_of_icons - 1) * separation
	
	ability_icons_container.position = Vector2(
		(cell_half_size - UI_PADDING) - container_width, 
		-cell_half_size + UI_PADDING                     
	)


func _update_finality_label_ui():
	if not is_instance_valid(finality_label): return
	if faction == Faction.UNDEAD and is_alive:
		finality_label.text = str(finality_counter)
		finality_label.visible = true
		# Adjust position based on its new text size
		var min_finality_size = finality_label.get_minimum_size()
		var cell_half_size = BattleGrid.CELL_SIZE / 2.0
		finality_label.position = Vector2(
			-cell_half_size + UI_PADDING, 
			(cell_half_size - UI_PADDING) - min_finality_size.y 
		)
	else:
		finality_label.visible = false
