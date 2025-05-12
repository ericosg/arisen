extends Node

@onready var level_label      : Label = $"../UI/Level"
@onready var max_de_label     : Label = $"../UI/MaxDarkEnergy"
@onready var current_de_label : Label = $"../UI/DarkEnergy"

var level        : int = 1
var max_base_de  : int = 1
var max_bonus_de : int = 0
var max_de       : int = 1
var current_de   : int = 1

var spells : Dictionary = {}

func _ready() -> void:
	# instantiate by class_name
	spells[Spell.SpellType.REANIMATE]  = SpellReanimate.new()
	spells[Spell.SpellType.SOUL_DRAIN] = SpellSoulDrain.new()

	_update_de()
	current_de = max_de
	_update_ui()

func cast_spell(spell_type: int, target = null) -> void:
	var spell = spells.get(spell_type)
	if spell == null:
		push_error("No spell of type %d" % spell_type)
		return

	var cost = spell.get_cost()
	if current_de < cost:
		_show_not_enough_de_popup()
		return

	current_de -= cost
	_update_ui()
	spell.do_effect(self, target)

func _update_de() -> void:
	max_base_de = int(round(sqrt(2 * level)))
	max_de      = max_base_de + max_bonus_de

func _update_ui() -> void:
	level_label.text      = "Level: %d" % level
	current_de_label.text = "DE: %d" % current_de
	max_de_label.text     = "MAX DE: %d" % max_de

func _show_not_enough_de_popup() -> void:
	print_debug("Not enough DE!")

# UI hooks
func _on_reanimate_pressed() -> void:
	cast_spell(Spell.SpellType.REANIMATE)

func _on_soul_drain_pressed() -> void:
	cast_spell(Spell.SpellType.SOUL_DRAIN)

func _on_level_up_pressed() -> void:
	level += 1
	_update_de()
	current_de = max_de
	_update_ui()

func _on_reanimate_levelup_pressed() -> void:
	spells[Spell.SpellType.REANIMATE].level_up()

func _on_soul_drain_levelup_pressed() -> void:
	spells[Spell.SpellType.SOUL_DRAIN].level_up()
