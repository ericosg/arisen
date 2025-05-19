# ./scripts/creatures/Creature.gd
extends Node2D
class_name Creature

# Signals
signal died(creature_instance: Creature) # Emitted when health reaches 0
signal health_changed(creature_instance: Creature, new_health: int, max_health: int)
signal grid_position_changed(creature_instance: Creature, new_grid_pos: Vector2i)
signal selection_changed(creature_instance: Creature, is_selected: bool) # For UI updates

# --- ENUMS ---
enum Faction { NONE, HUMAN, ALIEN, UNDEAD }
enum SpeedType { SLOW, NORMAL, FAST }

# --- CORE ATTRIBUTES ---
@export var creature_name: String = "Creature"
@export var level: int = 1 : set = _set_level 
@export var max_health: int = 10 : set = _set_max_health
@export var current_health: int = 10 : set = _set_current_health
@export var attack_power: int = 1

@export var faction: Faction = Faction.NONE
@export var speed_type: SpeedType = SpeedType.NORMAL

@export var is_flying: bool = false
@export var has_reach: bool = false

# --- STATE ---
var is_alive: bool = true
var is_targetable: bool = true # Can be targeted by spells/attacks
var grid_pos: Vector2i = Vector2i(-1, -1) : set = _set_grid_pos # (-1,-1) means not on grid

var is_selected: bool = false : set = _set_is_selected # For selection mechanic
var is_corpse: bool = false # True if this creature node represents a corpse visual

# Data payload for reanimation, populated from stats at time of death or init
var reanimation_payload_data: Dictionary = {
	"original_creature_name": "", "original_level": 1, "original_max_health": 0, 
	"original_attack_power": 0, "original_was_flying": false, 
	"original_had_reach": false, "original_faction": Faction.NONE,
	"corpse_texture_path": "" # Path to the corpse sprite for this creature type
}
@export var finality_counter: int = 0 : set = _set_finality_counter # Primarily for Undead

# --- CONFIGURATION ---
# This will be set from the config dictionary during initialize_creature
var corpse_texture_path_from_config: String = "res://icon.svg" # Default/fallback corpse sprite

# --- NODE REFERENCES ---
var game_manager: GameManager # Set by GameManager
var battle_grid: BattleGrid   # Set by GameManager

@onready var sprite_node_ref: Sprite2D = $Sprite # Assumes a child Sprite2D named "Sprite"

# --- UI ELEMENTS (Labels for stats, level, etc.) ---
const UI_FONT_SIZE: int = 12
const UI_PADDING: int = 2 # Adjusted padding slightly
const UI_ICON_SIZE: int = 16 
const PIXEL_FONT_BOLD: Font = preload("res://assets/fonts/PixelOperator8-Bold.ttf")

var stats_label: Label
var level_label: Label 
var ability_icons_container: HBoxContainer
var finality_label: Label 

# Placeholder textures for ability icons (ensure these paths are correct)
var icon_texture_flying: Texture2D = load("res://assets/images/icon_flying.png")
var icon_texture_reach: Texture2D = load("res://assets/images/icon_reach.png")
var icon_texture_speed_slow: Texture2D = load("res://assets/images/icon_speed_slow.png")
var icon_texture_speed_normal: Texture2D = load("res://assets/images/icon_speed_normal.png")
var icon_texture_speed_fast: Texture2D = load("res://assets/images/icon_speed_fast.png")

# Color for greyed-out UI text on corpses
const CORPSE_UI_COLOR: Color = Color(0.5, 0.5, 0.5, 1.0) # Grey
const SELECTION_MODULATE_COLOR: Color = Color(1.3, 1.3, 1.0, 1.0) # Brighter, slightly yellowish tint for selection


func _ready():
	_set_current_health(min(current_health, max_health)) # Ensure health is clamped on ready
	# _update_reanimation_payload_from_current_stats() is called after full initialization

	if not is_instance_valid(sprite_node_ref):
		printerr("Creature '%s' _ready(): Child Sprite2D node named 'Sprite' not found." % creature_name)

	_setup_ui_elements()
	# initialize_creature will call _update_all_ui_elements and _update_reanimation_payload
	
	health_changed.connect(_on_health_changed_ui_update)


func _setup_ui_elements():
	# Standard UI setup copied from your provided Creature.gd
	var cell_half_size = BattleGrid.CELL_SIZE / 2.0 

	stats_label = Label.new(); stats_label.name = "StatsLabel"
	stats_label.set_vertical_alignment(VERTICAL_ALIGNMENT_BOTTOM) 
	var stats_font_settings = FontVariation.new(); stats_font_settings.set_base_font(PIXEL_FONT_BOLD); stats_font_settings.set_variation_opentype({"size": UI_FONT_SIZE})
	stats_label.add_theme_font_override("font", stats_font_settings); stats_label.add_theme_font_size_override("font_size", UI_FONT_SIZE)
	stats_label.modulate = Color.WHITE; add_child(stats_label)

	level_label = Label.new(); level_label.name = "LevelLabel"
	level_label.set_horizontal_alignment(HORIZONTAL_ALIGNMENT_LEFT); level_label.set_vertical_alignment(VERTICAL_ALIGNMENT_TOP)
	var level_font_settings = FontVariation.new(); level_font_settings.set_base_font(PIXEL_FONT_BOLD); level_font_settings.set_variation_opentype({"size": UI_FONT_SIZE})
	level_label.add_theme_font_override("font", level_font_settings); level_label.add_theme_font_size_override("font_size", UI_FONT_SIZE)
	level_label.modulate = Color.WHITE; add_child(level_label)
	level_label.position = Vector2(-cell_half_size + UI_PADDING, -cell_half_size + UI_PADDING)

	ability_icons_container = HBoxContainer.new(); ability_icons_container.name = "AbilityIconsContainer"
	ability_icons_container.set_alignment(BoxContainer.ALIGNMENT_END); add_child(ability_icons_container)

	finality_label = Label.new(); finality_label.name = "FinalityLabel"
	finality_label.set_horizontal_alignment(HORIZONTAL_ALIGNMENT_LEFT); finality_label.set_vertical_alignment(VERTICAL_ALIGNMENT_BOTTOM)
	var finality_font_settings = FontVariation.new(); finality_font_settings.set_base_font(PIXEL_FONT_BOLD); finality_font_settings.set_variation_opentype({"size": UI_FONT_SIZE})
	finality_label.add_theme_font_override("font", finality_font_settings); finality_label.add_theme_font_size_override("font_size", UI_FONT_SIZE)
	finality_label.modulate = Color.WHITE; finality_label.visible = false; add_child(finality_label)
	# Position will be set in _update_finality_label_ui

func _update_reanimation_payload_from_current_stats():
	"""Populates the reanimation_payload_data dictionary with current or original stats."""
	reanimation_payload_data["original_creature_name"] = creature_name
	reanimation_payload_data["original_level"] = level
	reanimation_payload_data["original_max_health"] = max_health 
	reanimation_payload_data["original_attack_power"] = attack_power 
	reanimation_payload_data["original_was_flying"] = is_flying
	reanimation_payload_data["original_had_reach"] = has_reach
	reanimation_payload_data["original_faction"] = faction
	reanimation_payload_data["corpse_texture_path"] = corpse_texture_path_from_config # Use the path from config


# --- SETTERS ---
func _set_level(value: int):
	var old_level = level
	level = max(1, value)
	if old_level != level:
		if is_inside_tree(): _update_level_label_ui() # Update UI if level changes
		# _update_reanimation_payload_from_current_stats() # Called at init and death

func _set_max_health(value: int):
	max_health = max(1, value)
	if current_health > max_health: _set_current_health(max_health)
	else: 
		if is_inside_tree(): emit_signal("health_changed", self, current_health, max_health)
	# _update_reanimation_payload_from_current_stats() # Called at init and death

func _set_current_health(value: int):
	var old_health = current_health
	current_health = clamp(value, 0, max_health)
	if old_health != current_health:
		if is_inside_tree(): emit_signal("health_changed", self, current_health, max_health)
		if current_health <= 0 and is_alive: 
			die()

func _set_grid_pos(new_pos: Vector2i):
	if grid_pos != new_pos:
		var old_pos = grid_pos
		grid_pos = new_pos
		if is_inside_tree():
			if is_instance_valid(battle_grid) and battle_grid.is_valid_grid_position(grid_pos):
				# This creature is on the battle grid, update its world position
				self.position = battle_grid.get_world_position_for_grid_cell_center(grid_pos)
			elif new_pos == Vector2i(-1,-1) and old_pos != Vector2i(-1,-1):
				# Creature was removed from grid (e.g., returned to pool, or truly removed)
				# Its visual position might be handled by its new parent (e.g. UndeadPoolDisplay)
				# or it might be hidden if completely removed.
				pass
			elif new_pos != Vector2i(-1,-1) and not is_instance_valid(battle_grid):
				# This might happen if creature is in pool, not on grid.
				# Or if battle_grid reference is missing.
				# print_debug("Creature '%s': BattleGrid ref missing or invalid pos. Cannot update visual pos for %s." % [creature_name, str(new_pos)])
				pass 
			emit_signal("grid_position_changed", self, new_pos)

func _set_finality_counter(value: int):
	var old_finality = finality_counter
	finality_counter = max(0, value)
	if old_finality != finality_counter:
		if is_inside_tree(): 
			_update_finality_label_ui()
			if faction == Faction.UNDEAD and has_signal("undead_finality_changed"): # Specific signal for Undead
				emit_signal("undead_finality_changed", self, finality_counter)

func _set_is_selected(value: bool):
	"""Sets the selection state and updates visual feedback."""
	if is_selected != value:
		is_selected = value
		if is_instance_valid(sprite_node_ref):
			if is_selected:
				sprite_node_ref.modulate = SELECTION_MODULATE_COLOR
			else:
				sprite_node_ref.modulate = Color.WHITE # Normal modulation
		if is_inside_tree(): emit_signal("selection_changed", self, is_selected)

# --- CORE METHODS ---
func initialize_creature(config: Dictionary):
	creature_name = config.get("creature_name", "Default Name")
	# Store the corpse texture path from the configuration
	corpse_texture_path_from_config = config.get("corpse_texture_path", "res://icon.svg") # Fallback

	_set_level(config.get("level", 1)) 
	_set_max_health(config.get("max_health", 10))
	_set_current_health(max_health) 

	attack_power = config.get("attack_power", 1)
	faction = config.get("faction", Faction.NONE)
	speed_type = config.get("speed_type", SpeedType.NORMAL)
	is_flying = config.get("is_flying", false)
	has_reach = config.get("has_reach", false)

	if config.has("finality_counter"):
		_set_finality_counter(config.get("finality_counter", 0))

	_update_reanimation_payload_from_current_stats() # Crucial: Call after all stats are set
	is_alive = true
	is_targetable = true
	is_corpse = false # Ensure it's not a corpse on initialization

	var local_sprite_node: Sprite2D = get_node_or_null("Sprite") as Sprite2D
	if is_instance_valid(local_sprite_node):
		var texture_path = config.get("sprite_texture_path", "res://icon.svg")
		if ResourceLoader.exists(texture_path):
			var loaded_texture: Texture2D = load(texture_path)
			if is_instance_valid(loaded_texture):
				local_sprite_node.texture = loaded_texture
				local_sprite_node.scale = Vector2(1,1) # Ensure default scale
			else: 
				printerr("Creature '%s': Loaded resource at '%s' is NOT a valid Texture2D." % [creature_name, texture_path])
				local_sprite_node.texture = load("res://icon.svg") # Fallback
		else:
			printerr("Creature '%s': Texture path NOT FOUND: '%s'." % [creature_name, texture_path])
			local_sprite_node.texture = load("res://icon.svg") # Fallback
	else:
		printerr("Creature '%s': CRITICAL - Sprite node (child 'Sprite') MISSING." % creature_name)
	
	if is_inside_tree(): _update_all_ui_elements()


func take_damage(amount: int):
	if not is_alive or is_corpse or amount <= 0: return # Corpses don't take damage
	_set_current_health(current_health - amount)

func die():
	if not is_alive or is_corpse: return # Already dead or processing death
	is_alive = false
	is_targetable = false # Usually corpses aren't targetable by attacks
	is_corpse = true      # Mark this node as representing a corpse visual

	# Update the reanimation payload with stats at the moment of death
	_update_reanimation_payload_from_current_stats() 

	# Change sprite to corpse variant
	if is_instance_valid(sprite_node_ref):
		if ResourceLoader.exists(corpse_texture_path_from_config):
			var corpse_tex: Texture2D = load(corpse_texture_path_from_config)
			if is_instance_valid(corpse_tex):
				sprite_node_ref.texture = corpse_tex
				sprite_node_ref.modulate = Color(0.7, 0.7, 0.7, 0.9) # Dim the corpse sprite
			else:
				printerr("Creature '%s': Corpse texture at '%s' is not valid." % [creature_name, corpse_texture_path_from_config])
				sprite_node_ref.modulate = Color(0.5, 0.5, 0.5, 0.8) # Fallback dim
		else:
			printerr("Creature '%s': Corpse texture path '%s' not found." % [creature_name, corpse_texture_path_from_config])
			sprite_node_ref.modulate = Color(0.5, 0.5, 0.5, 0.8) # Fallback dim
	
	# Update UI to show corpse info (greyed out original stats)
	if is_inside_tree(): _update_all_ui_elements_for_corpse()
	
	if is_inside_tree(): emit_signal("died", self) # GameManager handles CorpseData resource creation

func can_attack_target(target_creature: Creature) -> bool:
	if not is_alive or is_corpse: return false # Corpses cannot attack
	if not is_instance_valid(target_creature) or not target_creature.is_alive or target_creature.is_corpse or not target_creature.is_targetable: return false
	if target_creature.faction == self.faction and self.faction != Faction.NONE: return false
	if target_creature.is_flying and not self.is_flying and not self.has_reach: return false
	return true

func get_tooltip_info() -> Dictionary: 
	if is_corpse:
		return {
			"name": "Corpse of %s" % reanimation_payload_data.get("original_creature_name", creature_name),
			"level": reanimation_payload_data.get("original_level", level),
			"health": "0/%s (Original)" % reanimation_payload_data.get("original_max_health", max_health),
			"attack": "%s (Original)" % reanimation_payload_data.get("original_attack_power", attack_power),
			"faction": Creature.Faction.keys()[reanimation_payload_data.get("original_faction", faction)],
			"finality": finality_counter, 
			"status": "Corpse - Targetable for Reanimate"
		}
	else: # Living creature
		return {
			"name": creature_name, "level": level, "health": "%d/%d" % [current_health, max_health], 
			"attack": attack_power, "speed": SpeedType.keys()[speed_type].to_lower(), 
			"is_flying": is_flying, "has_reach": has_reach, "faction": Faction.keys()[faction],
			"finality": finality_counter if faction == Faction.UNDEAD else "N/A"
		}

func get_data_for_corpse_creation() -> Dictionary:
	# This is called by GameManager when CorpseData resource is made.
	# Ensure payload is fresh, especially if stats could change just before death.
	_update_reanimation_payload_from_current_stats() # Ensure it reflects state at death
	var data = reanimation_payload_data.duplicate(true)
	if self.faction == Faction.UNDEAD: 
		data["current_finality_counter_on_death"] = self.finality_counter
	return data

# --- UI UPDATE FUNCTIONS ---
func _on_health_changed_ui_update(_creature, _new_health, _max_health):
	if not is_corpse: # Don't update health label if it's a corpse showing original stats
		_update_stats_label_ui()

func _update_all_ui_elements():
	if not is_inside_tree(): return
	if is_corpse:
		_update_all_ui_elements_for_corpse()
	else: # Living creature UI
		_update_stats_label_ui()
		_update_level_label_ui()
		_update_ability_icons_ui()
		_update_finality_label_ui() # Handles its own visibility based on faction/state

func _update_all_ui_elements_for_corpse():
	"""Special UI update for when the creature node represents a corpse."""
	if not is_inside_tree(): return

	# Stats Label: Show original Max HP and original Attack Power, greyed out
	if is_instance_valid(stats_label):
		stats_label.text = "%s/%s (RIP)" % [
			reanimation_payload_data.get("original_attack_power", "N/A"), 
			reanimation_payload_data.get("original_max_health", "N/A")
		]
		stats_label.modulate = CORPSE_UI_COLOR
		stats_label.set_horizontal_alignment(HORIZONTAL_ALIGNMENT_RIGHT)
		var min_size = stats_label.get_minimum_size(); stats_label.size = min_size 
		var label_size = stats_label.size; var cell_half_size = BattleGrid.CELL_SIZE / 2.0
		stats_label.position = Vector2((cell_half_size - UI_PADDING) - label_size.x, (cell_half_size - UI_PADDING) - label_size.y)
		stats_label.visible = true

	# Level Label: Show original level, greyed out
	if is_instance_valid(level_label):
		level_label.text = "L%s (RIP)" % reanimation_payload_data.get("original_level", "N/A")
		level_label.modulate = CORPSE_UI_COLOR
		level_label.visible = true
	
	# Ability Icons: Show original abilities, greyed out
	if is_instance_valid(ability_icons_container):
		for child in ability_icons_container.get_children(): child.queue_free() 
		var cell_half_size = BattleGrid.CELL_SIZE / 2.0; var number_of_icons = 0
		
		var original_speed = reanimation_payload_data.get("original_speed_type", speed_type) 
		var speed_icon_node = TextureRect.new(); speed_icon_node.custom_minimum_size = Vector2(UI_ICON_SIZE, UI_ICON_SIZE); speed_icon_node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; speed_icon_node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		match original_speed:
			SpeedType.SLOW: speed_icon_node.texture = icon_texture_speed_slow
			SpeedType.NORMAL: speed_icon_node.texture = icon_texture_speed_normal
			SpeedType.FAST: speed_icon_node.texture = icon_texture_speed_fast
		speed_icon_node.modulate = CORPSE_UI_COLOR; ability_icons_container.add_child(speed_icon_node); number_of_icons += 1

		if reanimation_payload_data.get("original_was_flying", false):
			var flying_icon_node = TextureRect.new(); flying_icon_node.texture = icon_texture_flying; flying_icon_node.custom_minimum_size = Vector2(UI_ICON_SIZE, UI_ICON_SIZE); flying_icon_node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; flying_icon_node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			flying_icon_node.modulate = CORPSE_UI_COLOR; ability_icons_container.add_child(flying_icon_node); number_of_icons += 1
		if reanimation_payload_data.get("original_had_reach", false):
			var reach_icon_node = TextureRect.new(); reach_icon_node.texture = icon_texture_reach; reach_icon_node.custom_minimum_size = Vector2(UI_ICON_SIZE, UI_ICON_SIZE); reach_icon_node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; reach_icon_node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			reach_icon_node.modulate = CORPSE_UI_COLOR; ability_icons_container.add_child(reach_icon_node); number_of_icons += 1
		
		ability_icons_container.visible = (number_of_icons > 0)
		if ability_icons_container.visible:
			var separation = ability_icons_container.get_theme_constant("separation", "HBoxContainer") if ability_icons_container.has_theme_constant("separation", "HBoxContainer") else 4
			var container_width = (number_of_icons * UI_ICON_SIZE) + (max(0, number_of_icons - 1) * separation)
			ability_icons_container.position = Vector2((cell_half_size - UI_PADDING) - container_width, -cell_half_size + UI_PADDING)
	
	# Finality Label: Show current finality (important for reanimation), greyed out
	if is_instance_valid(finality_label):
		if finality_counter >= 0 : # Show even if 0 for corpses, to indicate it's spent or was never high
			finality_label.text = "F:%d" % finality_counter
			finality_label.modulate = CORPSE_UI_COLOR
			finality_label.visible = true
			var min_finality_size = finality_label.get_minimum_size(); var cell_half_size = BattleGrid.CELL_SIZE / 2.0
			finality_label.position = Vector2(-cell_half_size + UI_PADDING, (cell_half_size - UI_PADDING) - min_finality_size.y)
		else: # Should not happen with finality_counter >= 0
			finality_label.visible = false


func _update_stats_label_ui(): # For living creatures
	if not is_inside_tree() or not is_instance_valid(stats_label): return
	if is_corpse: _update_all_ui_elements_for_corpse(); return 

	stats_label.text = "%d/%d" % [attack_power, current_health] 
	stats_label.modulate = Color.ORANGE_RED if current_health < max_health else Color.WHITE # Using your existing color
	stats_label.set_horizontal_alignment(HORIZONTAL_ALIGNMENT_RIGHT)
	var min_size = stats_label.get_minimum_size(); stats_label.size = min_size 
	var label_size = stats_label.size; var cell_half_size = BattleGrid.CELL_SIZE / 2.0
	stats_label.position = Vector2((cell_half_size - UI_PADDING) - label_size.x, (cell_half_size - UI_PADDING) - label_size.y)
	stats_label.visible = true

func _update_level_label_ui(): # For living creatures
	if not is_inside_tree() or not is_instance_valid(level_label): return
	if is_corpse: _update_all_ui_elements_for_corpse(); return

	level_label.text = "L%d" % level
	level_label.modulate = Color.WHITE
	level_label.visible = true

func _update_ability_icons_ui(): # For living creatures
	if not is_inside_tree() or not is_instance_valid(ability_icons_container): return
	if is_corpse: _update_all_ui_elements_for_corpse(); return

	for child in ability_icons_container.get_children(): child.queue_free()
	var cell_half_size = BattleGrid.CELL_SIZE / 2.0; var number_of_icons = 0

	var speed_icon_node = TextureRect.new(); speed_icon_node.custom_minimum_size = Vector2(UI_ICON_SIZE, UI_ICON_SIZE); speed_icon_node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; speed_icon_node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	match speed_type:
		SpeedType.SLOW: speed_icon_node.texture = icon_texture_speed_slow
		SpeedType.NORMAL: speed_icon_node.texture = icon_texture_speed_normal
		SpeedType.FAST: speed_icon_node.texture = icon_texture_speed_fast
	speed_icon_node.modulate = Color.WHITE; ability_icons_container.add_child(speed_icon_node); number_of_icons += 1

	if is_flying:
		var flying_icon_node = TextureRect.new(); flying_icon_node.texture = icon_texture_flying; flying_icon_node.custom_minimum_size = Vector2(UI_ICON_SIZE, UI_ICON_SIZE); flying_icon_node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; flying_icon_node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		flying_icon_node.modulate = Color.WHITE; ability_icons_container.add_child(flying_icon_node); number_of_icons += 1
	if has_reach:
		var reach_icon_node = TextureRect.new(); reach_icon_node.texture = icon_texture_reach; reach_icon_node.custom_minimum_size = Vector2(UI_ICON_SIZE, UI_ICON_SIZE); reach_icon_node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; reach_icon_node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		reach_icon_node.modulate = Color.WHITE; ability_icons_container.add_child(reach_icon_node); number_of_icons += 1
	
	ability_icons_container.visible = (number_of_icons > 0)
	if ability_icons_container.visible:
		var separation = ability_icons_container.get_theme_constant("separation", "HBoxContainer") if ability_icons_container.has_theme_constant("separation", "HBoxContainer") else 4
		var container_width = (number_of_icons * UI_ICON_SIZE) + (max(0, number_of_icons - 1) * separation)
		ability_icons_container.position = Vector2((cell_half_size - UI_PADDING) - container_width, -cell_half_size + UI_PADDING)

func _update_finality_label_ui(): # For living Undead
	if not is_inside_tree() or not is_instance_valid(finality_label): return
	if is_corpse: _update_all_ui_elements_for_corpse(); return

	if faction == Faction.UNDEAD and is_alive: 
		finality_label.text = "F:%d" % finality_counter
		finality_label.modulate = Color.WHITE
		finality_label.visible = true
		var min_finality_size = finality_label.get_minimum_size(); var cell_half_size = BattleGrid.CELL_SIZE / 2.0
		finality_label.position = Vector2(-cell_half_size + UI_PADDING, (cell_half_size - UI_PADDING) - min_finality_size.y)
	else:
		finality_label.visible = false

# Public method to set selection state, called by Game.gd
func set_selected(select_state: bool):
	_set_is_selected(select_state) # Call internal setter to trigger logic and signal
