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
@export var finality_counter: int = 0

# --- NODE REFERENCES ---
var game_manager: GameManager 
var battle_grid: BattleGrid   

@onready var sprite_node_ref: Sprite2D = $Sprite 


func _ready():
	_set_current_health(min(current_health, max_health))
	_update_reanimation_payload_from_current_stats()

	if not is_instance_valid(sprite_node_ref):
		printerr("Creature '%s' _ready(): Child Sprite2D node named 'Sprite' STILL not found by @onready var." % creature_name)


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
	if current_health > max_health: _set_current_health(max_health)
	emit_signal("health_changed", self, current_health, max_health)

func _set_current_health(value: int):
	var old_health = current_health
	current_health = clamp(value, 0, max_health)
	if old_health != current_health:
		emit_signal("health_changed", self, current_health, max_health)
		if current_health <= 0 and is_alive: die()

func _set_grid_pos(new_pos: Vector2i):
	if grid_pos != new_pos:
		grid_pos = new_pos
		if is_instance_valid(battle_grid): 
			self.position = battle_grid.get_world_position_for_grid_cell_center(grid_pos)
			# print_debug("Creature '%s' visual position set to %s for grid_pos %s" % [creature_name, str(self.position), str(new_pos)])
		elif new_pos != Vector2i(-1,-1): 
			printerr("Creature '%s': BattleGrid ref missing. Cannot update visual pos for %s." % [creature_name, str(new_pos)])
		emit_signal("grid_position_changed", self, new_pos)

# --- CORE METHODS ---
func initialize_creature(config: Dictionary):
	creature_name = config.get("creature_name", "Default Name")
	_set_max_health(config.get("max_health", 10))
	_set_current_health(max_health) 
	attack_power = config.get("attack_power", 1)
	faction = config.get("faction", Faction.NONE)
	speed_type = config.get("speed_type", SpeedType.NORMAL)
	is_flying = config.get("is_flying", false)
	has_reach = config.get("has_reach", false)

	_update_reanimation_payload_from_current_stats()

	if config.has("finality_counter"):
		finality_counter = config.get("finality_counter", 0)

	is_alive = true
	is_targetable = true

	var local_sprite_node: Sprite2D = get_node_or_null("Sprite") as Sprite2D

	if is_instance_valid(local_sprite_node):
		var texture_path = config.get("sprite_texture_path", "res://icon.svg") 
		# print_debug("Creature '%s': Configured texture path: '%s'" % [creature_name, texture_path])
		
		if ResourceLoader.exists(texture_path):
			var loaded_texture: Texture2D = load(texture_path)
			if is_instance_valid(loaded_texture): # Check if load was successful and is a Texture2D
				local_sprite_node.texture = loaded_texture
				# print_debug("Creature '%s': Successfully loaded texture: '%s'" % [creature_name, texture_path])

				# --- ADD SCALING LOGIC HERE ---
				var texture_size = loaded_texture.get_size()
				if texture_size.x > 0 and texture_size.y > 0 and is_instance_valid(battle_grid):
					var cell_s = float(battle_grid.CELL_SIZE) # Ensure float division
					# To fit within the cell, maintaining aspect ratio, use the smaller scale factor
					var scale_x = cell_s / texture_size.x
					var scale_y = cell_s / texture_size.y
					var final_scale = min(scale_x, scale_y) 
					
					# If you want a little padding, reduce the scale further:
					# final_scale *= 0.9 # e.g., 90% of cell size
					
					local_sprite_node.scale = Vector2(final_scale, final_scale)
					# print_debug("Creature '%s': Scaled sprite from %s to fit %sx%s cell. Scale factor: %s" % [creature_name, str(texture_size), str(battle_grid.CELL_SIZE), str(battle_grid.CELL_SIZE), str(local_sprite_node.scale)])
				elif not is_instance_valid(battle_grid):
					printerr("Creature '%s': BattleGrid reference missing, cannot calculate scale for sprite." % creature_name)
				# --- END SCALING LOGIC ---

			else:
				printerr("Creature '%s': Loaded resource at '%s' is NOT a valid Texture2D. Using default." % [creature_name, texture_path])
				local_sprite_node.texture = load("res://icon.svg") 
		else:
			printerr("Creature '%s': Texture path NOT FOUND: '%s'. Using default icon." % [creature_name, texture_path])
			local_sprite_node.texture = load("res://icon.svg") 
	else:
		printerr("Creature '%s': CRITICAL - Sprite node (child 'Sprite') MISSING in initialize_creature." % creature_name)


func take_damage(amount: int): # ... (same as before)
	if not is_alive or amount <= 0: return
	_set_current_health(current_health - amount)

func die(): # ... (same as before)
	if not is_alive: return
	is_alive = false; is_targetable = false
	emit_signal("died", self)

func can_attack_target(target_creature: Creature) -> bool: # ... (same as before)
	if not is_instance_valid(target_creature) or not target_creature.is_alive or not target_creature.is_targetable: return false
	if not self.is_alive: return false
	if target_creature.faction == self.faction and self.faction != Faction.NONE: return false
	if target_creature.is_flying and not self.is_flying and not self.has_reach: return false
	return true

func get_tooltip_info() -> Dictionary: # ... (same as before)
	return {
		"name": creature_name, "health": "%d/%d" % [current_health, max_health], "attack": attack_power,
		"speed": SpeedType.keys()[speed_type].to_lower(), "is_flying": is_flying, "has_reach": has_reach,
		"faction": Faction.keys()[faction],
		"finality": finality_counter if faction == Faction.UNDEAD else "N/A"
	}

func get_data_for_corpse_creation() -> Dictionary: # ... (same as before)
	var corpse_data = reanimation_payload_data.duplicate(true)
	if self.faction == Faction.UNDEAD:
		corpse_data["current_finality_counter_on_death"] = self.finality_counter
	return corpse_data
