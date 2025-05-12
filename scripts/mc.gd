extends Node

@onready var level_label: Label = $"../UI/Level"
@onready var max_dark_energy_label: Label = $"../UI/MaxDarkEnergy"
@onready var dark_energy_label: Label = $"../UI/DarkEnergy"

var level = 1
var max_base_de = 1
var max_bonus_de = 0
var max_de = 1
var current_de = 1


func _ready() -> void:
	_update_ui()


func level_up():
	level += 1
	_update_de()
	current_de = max_de
	_update_ui()


func _update_ui():
	level_label.text = "Level: " + str(level)
	dark_energy_label.text = "DE: " + str(current_de)
	max_dark_energy_label.text = "MAX DE: " + str(max_de)


func _update_de():
	max_base_de = _calculate_max_base_de(level)
	max_de = max_base_de + max_bonus_de


func _calculate_max_base_de(level):
	return int( round( sqrt(2 * level) ) )


func _on_level_up_pressed() -> void:
	level_up()


func _on_reanimate_pressed() -> void:
	current_de = current_de - 1
