# Creature.gd - Base class for all creatures
class_name Creature
extends Node2D

enum SpeedType {
	SLOW = 0,
	NORMAL = 1,
	FAST = 2
}

enum Type {
	HUMAN = 0,
	ALIEN = 1,
	UNDEAD = 2
}

var attack_power    : int  = 1
var max_health      : int  = 1
var current_health  : int  = 1
var speed_type      : int  = SpeedType.NORMAL
var is_flying       : bool = false
var has_reach       : bool = false
var creature_type   : int  = Type.HUMAN
var finality_counter: int  = 0  # Used only for undead

# Positioning
var row             : int  = 0
var lane            : int  = 0

func _init(attack: int = 1, health: int = 1, speed: int = SpeedType.NORMAL, flying: bool = false, reach: bool = false) -> void:
	attack_power = attack
	max_health = health
	current_health = health
	speed_type = speed
	is_flying = flying
	has_reach = reach

func take_damage(amount: int) -> void:
	current_health -= amount
	if current_health <= 0:
		die()

func die() -> void:
	# Override in child classes
	queue_free()

func can_attack(target: Creature) -> bool:
	# Flying creatures can attack any creature
	if is_flying:
		return true
	
	# Non-flying creatures can only attack non-flying creatures
	return not target.is_flying

func can_defend_against(attacker: Creature) -> bool:
	# Any creature can defend against non-flying attackers
	if not attacker.is_flying:
		return true
	
	# Only flying creatures or creatures with reach can defend against flying
	return is_flying or has_reach

func heal(amount: int) -> void:
	current_health = min(current_health + amount, max_health)

func get_display_stats() -> String:
	return "%d/%d" % [attack_power, current_health]

func get_speed_name() -> String:
	match speed_type:
		SpeedType.SLOW:
			return "Slow"
		SpeedType.NORMAL:
			return "Normal" 
		SpeedType.FAST:
			return "Fast"
		_:
			return "Unknown"

func is_dead() -> bool:
	return current_health <= 0
