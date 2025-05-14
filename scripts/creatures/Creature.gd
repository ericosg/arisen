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

# This @onready var is for convenience in methods called *after* _ready().
# GameManager._prepare_creature_node_base() adds a Sprite2D child named "Sprite".
@onready var sprite_node_ref: Sprite2D = $Sprite 


func _ready():
	_set_current_health(min(current_health, max_health))
	_update_reanimation_payload_from_current_stats()

	if not is_instance_valid(sprite_node_ref):
		printerr("Creature '%s' _ready(): Child Sprite2D node named 'Sprite' STILL not found by @onready var. This is unexpected if GameManager created it." % creature_name)


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
		elif new_pos != Vector2i(-1,-1): 
			printerr("Creature '%s': BattleGrid ref missing. Cannot update visual pos for %s." % [creature_name, str(new_pos)])
		emit_signal("grid_position_changed", self, new_pos)

# --- CORE METHODS ---
func initialize_creature(config: Dictionary):
	creature_name = config.get("creature_name", "Default Name")
	_set_max_health(config.get("max_health", 10))
	_set_current_health(max_health) # Start with full health
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

	# Attempt to get the Sprite2D child node directly.
	# GameManager's _prepare_creature_node_base should have created this child.
	var local_sprite_node: Sprite2D = get_node_or_null("Sprite") as Sprite2D

	if is_instance_valid(local_sprite_node):
		var texture_path = config.get("sprite_texture_path", "res://icon.svg") # Default to Godot icon
		# print_debug("Creature '%s': Attempting to load texture from config path: '%s'" % [creature_name, texture_path])
		
		if ResourceLoader.exists(texture_path):
			var loaded_texture = load(texture_path)
			if loaded_texture is Texture2D:
				local_sprite_node.texture = loaded_texture
				# print_debug("Creature '%s': Successfully loaded and set texture: '%s'" % [creature_name, texture_path])
			else:
				printerr("Creature '%s': Loaded resource at '%s' is not a Texture2D. Type is: %s" % [creature_name, texture_path, typeof(loaded_texture)])
				local_sprite_node.texture = load("res://icon.svg") # Fallback
		else:
			printerr("Creature '%s': Texture path NOT FOUND: '%s'. Using default icon." % [creature_name, texture_path])
			local_sprite_node.texture = load("res://icon.svg") # Fallback
	else:
		# This error means _prepare_creature_node_base in GameManager didn't work as expected or was bypassed.
		printerr("Creature '%s': CRITICAL - Sprite node (child named 'Sprite') is MISSING in initialize_creature. Cannot set texture." % creature_name)


func take_damage(amount: int):
	if not is_alive or amount <= 0: return
	_set_current_health(current_health - amount)

func die():
	if not is_alive: return
	is_alive = false; is_targetable = false
	emit_signal("died", self)
	# if is_instance_valid(sprite_node_ref): sprite_node_ref.visible = false # Example: hide on death

func can_attack_target(target_creature: Creature) -> bool:
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
