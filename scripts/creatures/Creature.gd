# Creature.gd - Base class for all creatures
class_name Creature
extends Node2D # Creatures are visual and have a position

enum SpeedType {
	SLOW = 0,
	NORMAL = 1,
	FAST = 2
}

enum CreatureFaction { # More descriptive than just 'Type'
	HUMAN = 0,
	ALIEN = 1,
	UNDEAD = 2 # Undead are on the player's (defender) side
}

@export var attack_power: int = 1
@export var max_health: int = 1
var current_health: int = 1
@export var speed_type: SpeedType = SpeedType.NORMAL
@export var is_flying: bool = false
@export var has_reach: bool = false # Can attack non-adjacent enemies or hit flyers easily

var faction: CreatureFaction = CreatureFaction.HUMAN # Default, override in subclasses
var finality_counter: int = 0 # Used only for Undead

# Grid positioning (managed by BattleGrid/GameManager)
var row: int = -1 # Screen row
var lane: int = -1 # Column

# Signal emitted when health changes, useful for UI or effects
signal health_changed(current, max)
signal died(creature_instance) # Emitted when health drops to 0

func _init(ap: int = 1, hp: int = 1, spd: SpeedType = SpeedType.NORMAL, flying: bool = false, reach: bool = false) -> void:
	attack_power = ap
	max_health = hp
	current_health = hp # Start with full health
	speed_type = spd
	is_flying = flying
	has_reach = reach
	# Ensure current_health is set after max_health if not done in constructor
	# current_health = max_health # Already done by assignment

func _ready():
	current_health = max_health # Ensure health is full at start if values set in editor
	# Add a simple visual placeholder if no sprite is set
	if get_child_count() == 0:
		var placeholder = ColorRect.new()
		placeholder.size = Vector2(32, 32)
		placeholder.color = Color.GRAY
		add_child(placeholder)
		var label = Label.new()
		label.text = self.get_class().substr(0,1)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.size = placeholder.size
		placeholder.add_child(label)


func take_damage(amount: int) -> void:
	current_health = max(0, current_health - amount)
	emit_signal("health_changed", current_health, max_health)
	# print("%s took %d damage, health is now %d/%d" % [self.name, amount, current_health, max_health])
	if current_health <= 0:
		die()

func die() -> void:
	# This is the generic die function. Subclasses will override it
	# to handle specific death logic (e.g., Undead finality).
	print("%s (generic) at %s,%s has died." % [self.get_class(), lane, row])
	emit_signal("died", self) # Signal that this creature instance has effectively died
	
	# The GameManager's handle_creature_death will do the actual cleanup from lists and grid.
	# It's crucial that queue_free() is called eventually.
	# Typically, the class calling die() or GameManager will queue_free.
	# Let's make it a rule: the die() method itself is responsible for queue_free IF NOT HANDLED BY UNDEAD LOGIC.
	if not self is Undead : # Undead has its own queue_free logic based on finality
		queue_free()


func can_attack(target: Creature) -> bool:
	if not is_instance_valid(target): return false
	# Basic rules:
	# 1. Cannot attack own faction (unless specific rules apply, e.g. mind control)
	# This check should probably be in GameManager's combat logic
	# if self.faction == target.faction: return false # For now, assume GM handles this

	# 2. Flying vs Ground interaction
	if is_flying:
		return true # Flying can attack ground and other flying units
	else: # Grounded attacker
		if target.is_flying and not has_reach:
			return false # Grounded without reach cannot hit flyers
		return true # Grounded can hit other grounded, or flyers if has_reach

func can_be_attacked_by(attacker: Creature) -> bool: # Inverse of can_attack, from target's perspective
	if not is_instance_valid(attacker): return false
	if attacker.is_flying:
		if is_flying: return true # Flyer vs Flyer
		return not has_reach # Grounded unit needs reach to defend vs flyer effectively (placeholder idea)
							 # More standard: flyers can always hit ground. Ground needs reach/flying to hit back.
							 # So, if attacker is flying, this unit *can* be attacked.
		return true
	else: # Grounded attacker
		return true # Grounded attackers can always attempt to hit (unless target is flying and attacker has no reach)

func heal(amount: int) -> void:
	current_health = min(max_health, current_health + amount)
	emit_signal("health_changed", current_health, max_health)

func get_display_stats() -> String:
	return "%d/%d" % [attack_power, current_health]

func get_speed_name() -> String:
	match speed_type:
		SpeedType.SLOW: return "Slow"
		SpeedType.NORMAL: return "Normal"
		SpeedType.FAST: return "Fast"
		_: return "Unknown"

func is_dead() -> bool:
	return current_health <= 0

# Movement distance per turn - NO LONGER USED FOR GameManager.move_creatures
# Kept for potential future use or other speed-based calculations.
func get_move_distance_per_turn() -> int:
	match speed_type:
		SpeedType.SLOW: return 1
		SpeedType.NORMAL: return 2
		SpeedType.FAST: return 3
		_: return 0
