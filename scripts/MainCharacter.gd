extends Node

@onready var level_label            : Label = $"../UI/Level"
@onready var max_dark_energy_label  : Label = $"../UI/MaxDarkEnergy"
@onready var dark_energy_label      : Label = $"../UI/DarkEnergy"

var level           : int = 1
var max_base_de     : int = 1
var max_bonus_de    : int = 0
var max_de          : int = 1
var current_de      : int = 1

var spells = {
	Spell.SpellType.REANIMATE:  preload("res://resources/SpellReanimate.tres")  as Spell,
	Spell.SpellType.SOUL_DRAIN:  preload("res://resources/SpellSoulDrain.tres") as Spell,
}

func _ready() -> void:
	_update_de()
	current_de = max_de
	_update_ui()

func level_up() -> void:
	level += 1
	_update_de()
	current_de = max_de
	_update_ui()

func _update_de() -> void:
	max_base_de = _calculate_max_base_de(level)
	max_de      = max_base_de + max_bonus_de

func _calculate_max_base_de(lvl: int) -> int:
	return int( round( sqrt(2 * lvl) ) )

func _update_ui() -> void:
	level_label.text           = "Level: %d" % level
	dark_energy_label.text     = "DE: %d" % current_de
	max_dark_energy_label.text = "MAX DE: %d" % max_de

func cast_spell(spell_type: int) -> void:
	var spell = spells.get(spell_type)
	if spell == null:
		push_error("Unknown spell type %d" % spell_type)
		return

	var cost = spell.get_cost(level)
	if current_de < cost:
		_show_not_enough_de_popup()
		return

	current_de -= cost
	_update_ui()

	match spell_type:
		Spell.SpellType.REANIMATE:
			_perform_reanimate()
		Spell.SpellType.SOUL_DRAIN:
			_perform_soul_drain()
		_:
			pass

func _on_reanimate_pressed() -> void:
	cast_spell( Spell.SpellType.REANIMATE )

func _on_soul_drain_pressed() -> void:
	cast_spell( Spell.SpellType.SOUL_DRAIN )

func _on_level_up_pressed() -> void:
	level_up()

func _perform_reanimate() -> void:
	pass

func _perform_soul_drain() -> void:
	pass

func _show_not_enough_de_popup() -> void:
	print_debug("not enough energy!")
	pass
