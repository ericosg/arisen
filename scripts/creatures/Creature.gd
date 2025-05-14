# ./scripts/creatures/Creature.gd
extends Node2D
class_name Creature

# Signals
# Emitted when current_health <= 0. The instance of the creature that died is passed.
signal died(creature_instance: Creature)
# Emitted when health changes. Useful for UI updates or other logic.
signal health_changed(creature_instance: Creature, new_health: int, max_health: int)
# Emitted when the creature's logical grid position changes.
signal grid_position_changed(creature_instance: Creature, new_grid_pos: Vector2i)

# --- ENUMS ---
# Defines the creature's allegiance. UNDEAD are player-allied.
enum Faction { NONE, HUMAN, ALIEN, UNDEAD }
# Defines the creature's movement/placement category.
enum SpeedType { SLOW, NORMAL, FAST }

# --- CORE ATTRIBUTES ---
# These are exported for easy viewing in the inspector if you attach this script
# to a base Creature node, but they will typically be overridden by initialize_creature().
@export var creature_name: String = "Creature"
@export var max_health: int = 10 : set = _set_max_health
@export var current_health: int = 10 : set = _set_current_health
@export var attack_power: int = 1

@export var faction: Faction = Faction.NONE
@export var speed_type: SpeedType = SpeedType.NORMAL

@export var is_flying: bool = false
@export var has_reach: bool = false # Allows ground units to engage flying units in the same lane

# --- STATE ---
var is_alive: bool = true
var is_targetable: bool = true # Usually tied to is_alive
var grid_pos: Vector2i = Vector2i(-1, -1) : set = _set_grid_pos # (column, row)

# --- DATA FOR REANIMATION (Stored on the creature, passed to Corpse object on death) ---
# These store the creature's state *before* any modifications due to being undead,
# relevant if an Alien or Human is reanimated.
var reanimation_payload_data: Dictionary = {
	"original_creature_name": "",
	"original_max_health": 0,
	"original_attack_power": 0,
	"original_was_flying": false,
	"original_had_reach": false,
	"original_faction": Faction.NONE
}

# Finality counter is primarily for Undead creatures.
# It will be explicitly managed in Undead.gd and by reanimation spells.
@export var finality_counter: int = 0


# --- NODE REFERENCES (Assign in _ready or via direct assignment from parent/manager) ---
# Example:
# @onready var game_manager: GameManager = get_tree().get_root().find_child("GameManagerNodeName", true, false)
# @onready var battle_grid: BattleGrid = get_tree().get_root().find_child("BattleGridNodeName", true, false)
# It's often cleaner if the node that spawns/manages creatures sets these references.
var game_manager # Needs to be assigned (e.g., by GameManager when creature is added)
var battle_grid # Needs to be assigned


func _ready():
	# Ensure current_health doesn't exceed max_health initially.
	# This also correctly calls the setter if values need clamping.
	_set_current_health(min(current_health, max_health))

	# Populate reanimation_payload_data with initial values.
	# This should ideally be done *before* any modifications if this creature instance
	# itself becomes an Undead (though typically a new Undead instance is made).
	# For now, this captures the state as defined at export/initialization time.
	reanimation_payload_data["original_creature_name"] = creature_name
	reanimation_payload_data["original_max_health"] = max_health
	reanimation_payload_data["original_attack_power"] = attack_power
	reanimation_payload_data["original_was_flying"] = is_flying
	reanimation_payload_data["original_had_reach"] = has_reach
	reanimation_payload_data["original_faction"] = faction
	
	# --- Signal Connections Example (if this node needs to listen to its own signals, which is rare) ---
	# More commonly, other nodes (like a UI handler or GameManager) would connect to these.
	# Example: self.health_changed.connect(_on_my_own_health_changed)


# --- SETTERS (for validation, signal emission, and side effects) ---
func _set_max_health(value: int):
	max_health = value
	if max_health < 1:
		max_health = 1 # Health should not be less than 1
	
	# If current health is now greater than new max, clamp it
	if current_health > max_health:
		_set_current_health(max_health) # Use setter to ensure signals/logic fire
	
	emit_signal("health_changed", self, current_health, max_health)

func _set_current_health(value: int):
	var old_health = current_health
	current_health = clamp(value, 0, max_health)
	
	if old_health != current_health:
		emit_signal("health_changed", self, current_health, max_health)
		if current_health <= 0 and is_alive: # Check is_alive to prevent multiple die() calls
			die()

func _set_grid_pos(new_pos: Vector2i):
	if grid_pos != new_pos:
		grid_pos = new_pos
		# Optional: Update visual position of this Node2D based on grid_pos.
		# This requires knowing CELL_SIZE from BattleGrid.
		# if is_instance_valid(battle_grid):
		#    self.position = Vector2(new_pos.x * battle_grid.CELL_SIZE + battle_grid.CELL_SIZE / 2.0, \
		#                            new_pos.y * battle_grid.CELL_SIZE + battle_grid.CELL_SIZE / 2.0)
		emit_signal("grid_position_changed", self, new_pos)


# --- CORE METHODS ---
# Call this to configure a creature instance after it's created.
func initialize_creature(config: Dictionary):
	creature_name = config.get("creature_name", "Default Name")
	
	# Use setters to ensure logic (like clamping, signal emission) is applied
	_set_max_health(config.get("max_health", 10))
	_set_current_health(max_health) # Start with full health by default
	
	attack_power = config.get("attack_power", 1)
	
	# Convert integer from config to enum if necessary, or ensure config passes enum value
	faction = config.get("faction", Faction.NONE) 
	speed_type = config.get("speed_type", SpeedType.NORMAL)
	
	is_flying = config.get("is_flying", false)
	has_reach = config.get("has_reach", false)
	
	# Update reanimation payload with these initialized values
	reanimation_payload_data["original_creature_name"] = creature_name
	reanimation_payload_data["original_max_health"] = max_health
	reanimation_payload_data["original_attack_power"] = attack_power
	reanimation_payload_data["original_was_flying"] = is_flying
	reanimation_payload_data["original_had_reach"] = has_reach
	reanimation_payload_data["original_faction"] = faction

	# Finality counter is usually set for Undead specifically.
	# If config provides it (e.g. loading a saved Undead state), set it.
	if config.has("finality_counter"):
		finality_counter = config.get("finality_counter", 0)

	is_alive = true
	is_targetable = true
	
	# TODO: Add logic here to update the creature's visual representation
	# (e.g., load a specific sprite sheet based on creature_name or type from config)
	# Example: if has_node("Sprite2D"): get_node("Sprite2D").texture = load("res://path_to_sprite.png")

func take_damage(amount: int):
	if not is_alive or amount <= 0: # Can't damage dead creatures or with non-positive damage
		return

	# print_debug("%s takes %d damage. Current health: %d" % [creature_name, amount, current_health])
	_set_current_health(current_health - amount) # Use setter

func die():
	if not is_alive: # Ensure die() is only processed once
		return

	# print_debug("%s has died." % creature_name)
	is_alive = false
	is_targetable = false # Dead creatures usually cannot be targeted for attacks
	
	# The GameManager will listen to this signal.
	# It will then create a Corpse object using get_reanimation_data_payload()
	# and manage removing this Creature node from the active game.
	emit_signal("died", self)
	
	# Optional:
	# - Play a death animation.
	# - After animation, you might hide the creature (visible = false)
	#   while GameManager decides on corpse/removal.
	# - GameManager should ultimately queue_free() this node if it's removed from play.

# Checks if this creature can attack a specific target based on game rules.
# Note: Lane positioning checks are handled by the combat resolution logic in GameManager/BattleGrid.
func can_attack_target(target_creature: Creature) -> bool:
	if not is_instance_valid(target_creature) or not target_creature.is_alive or not target_creature.is_targetable:
		return false # Target is invalid, dead, or untargetable
	if not self.is_alive:
		return false # This creature cannot attack if dead
	
	# Prevent attacking own faction (unless it's Faction.NONE, for testing perhaps)
	if target_creature.faction == self.faction and self.faction != Faction.NONE:
		return false
	
	# Flying vs. Ground without Reach:
	# If the target is flying, and this attacker is on the ground and lacks reach, it cannot attack.
	if target_creature.is_flying and not self.is_flying and not self.has_reach:
		return false

	return true

# Provides a dictionary of information for UI display (e.g., tooltips).
func get_tooltip_info() -> Dictionary:
	return {
		"name": creature_name,
		"health": "%d/%d" % [current_health, max_health],
		"attack": attack_power,
		"speed": SpeedType.keys()[speed_type].to_lower(), # e.g., "slow", "normal", "fast"
		"is_flying": is_flying,
		"has_reach": has_reach,
		"faction": Faction.keys()[faction], # e.g., "HUMAN", "ALIEN"
		"finality": finality_counter if faction == Faction.UNDEAD else "N/A"
	}

# Call this when the creature dies to get data needed for creating a Corpse object.
func get_data_for_corpse_creation() -> Dictionary:
	var corpse_data = reanimation_payload_data.duplicate(true) # Deep copy
	# If this creature was Undead, its current finality_counter is what matters for the corpse.
	# Otherwise, the corpse will get a default starting finality from GameManager/ReanimateSpell.
	if self.faction == Faction.UNDEAD:
		corpse_data["current_finality_counter_on_death"] = self.finality_counter
	return corpse_data

# --- Example of connecting to a signal from another node ---
# func _on_some_other_node_emitted_a_signal(data):
#    pass

# You might have an AnimationPlayer node as a child for animations.
# func play_animation(anim_name: String):
#    if has_node("AnimationPlayer"):
#        get_node("AnimationPlayer").play(anim_name)
