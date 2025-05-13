# Necromancer.gd
extends Node
@onready var level_label              : Label  = $"../UI/Level"
@onready var max_de_label             : Label  = $"../UI/MaxDarkEnergy"
@onready var current_de_label         : Label  = $"../UI/DarkEnergy"
@onready var mastery_label            : Label  = $"../UI/MasteryPoints"
@onready var reanimate_button         : Button = $"../UI/Reanimate"
@onready var soul_drain_button        : Button = $"../UI/SoulDrain"
@onready var reanimate_upgrade_button : Button = $"../UI/ReanimateUpgrade"
@onready var soul_drain_upgrade_button : Button = $"../UI/SoulDrainUpgrade"

var level        : int = 1
var max_base_de  : int = 1
var max_bonus_de : int = 0
var max_de       : int = 1
var current_de   : int = 1
var mastery      : int = 0
var spells : Dictionary[int, Spell] = {}

func _ready() -> void:
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
	var cost = spell.get_de_cost()
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
	level_label.text       = "Level: %d" % level
	current_de_label.text  = "Dark Energy (DE): %d" % current_de
	max_de_label.text      = "Max DE: %d" % max_de
	mastery_label.text     = "Mastery Points (MP): %d" % mastery
	
	var reanimate_cost = spells[Spell.SpellType.REANIMATE].get_de_cost()
	var soul_drain_cost = spells[Spell.SpellType.SOUL_DRAIN].get_de_cost()
	
	reanimate_button.text = "REANIMATE %d (%d DE)" % [spells[Spell.SpellType.REANIMATE].level, reanimate_cost]
	soul_drain_button.text = "SOUL DRAIN %d (%d DE)" % [spells[Spell.SpellType.SOUL_DRAIN].level, soul_drain_cost]
	
	reanimate_button.disabled = current_de < reanimate_cost
	soul_drain_button.disabled = current_de < soul_drain_cost
	
	var reanimate_mastery_cost = spells[Spell.SpellType.REANIMATE].get_mastery_cost()
	var soul_drain_mastery_cost = spells[Spell.SpellType.SOUL_DRAIN].get_mastery_cost()
	
	if reanimate_upgrade_button:
		reanimate_upgrade_button.text = "Upgrade (%d MP)" % reanimate_mastery_cost
		reanimate_upgrade_button.disabled = mastery < reanimate_mastery_cost
	
	if soul_drain_upgrade_button:
		soul_drain_upgrade_button.text = "Upgrade (%d MP)" % soul_drain_mastery_cost
		soul_drain_upgrade_button.disabled = mastery < soul_drain_mastery_cost

func _show_not_enough_de_popup() -> void:
	print_debug("Not enough DE!")

func _show_not_enough_mastery_popup() -> void:
	print_debug("Not enough Mastery Points!")

# UI hooks
func _on_reanimate_pressed() -> void:
	cast_spell(Spell.SpellType.REANIMATE)

func _on_soul_drain_pressed() -> void:
	cast_spell(Spell.SpellType.SOUL_DRAIN)

func _on_level_up_pressed() -> void:
	level += 1
	mastery += 1
	_update_de()
	current_de = max_de
	_update_ui()

func _on_reanimate_upgrade_pressed() -> void:
	_attempt_spell_level_up(Spell.SpellType.REANIMATE)

func _on_soul_drain_upgrade_pressed() -> void:
	_attempt_spell_level_up(Spell.SpellType.SOUL_DRAIN)

func _attempt_spell_level_up(spell_type: int) -> void:
	var spell = spells.get(spell_type)
	if spell == null:
		push_error("No spell of type %d" % spell_type)
		return
	
	var cost = spell.get_mastery_cost()
	if mastery < cost:
		_show_not_enough_mastery_popup()
		return
	
	mastery -= cost
	spell.level_up()
	_update_ui()
