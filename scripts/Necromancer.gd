# Necromancer.gd
extends Node # Or whatever base node you use for the Necromancer actor/manager

# UI Connections (ensure these paths are correct in your scene)
@onready var level_label: Label = $"../UI/Level" # Example path
@onready var max_de_label: Label = $"../UI/MaxDarkEnergy"
@onready var current_de_label: Label = $"../UI/DarkEnergy"
@onready var mastery_label: Label = $"../UI/MasteryPoints"
@onready var reanimate_button: Button = $"../UI/Reanimate"
@onready var soul_drain_button: Button = $"../UI/SoulDrain"
@onready var reanimate_upgrade_button: Button = $"../UI/ReanimateUpgrade"
@onready var soul_drain_upgrade_button: Button = $"../UI/SoulDrainUpgrade"
# Add reference to the ReanimateTypeButton if it's part of Necromancer's direct UI control
@onready var reanimate_type_button: Button = $"../UI/ReanimateType" # Example path
@onready var game_manager: GameManager = $"../GameManager"


var level: int = 1
var max_base_de: int = 10 # Initial DE
var max_bonus_de: int = 0
var max_de: int = 10
var current_de: int = 10
var mastery_points: int = 0 # Renamed from 'mastery' for clarity

var spells: Dictionary = {} # Using Dictionary directly

func _ready() -> void:
	spells[Spell.SpellType.REANIMATE] = SpellReanimate.new()
	spells[Spell.SpellType.SOUL_DRAIN] = SpellSoulDrain.new()

	# Connect UI signals if they are children of this node or set up in editor
	if is_instance_valid(reanimate_button):
		reanimate_button.connect("pressed", Callable(self, "_on_reanimate_button_pressed"))
	# ... connect other buttons similarly ...
	if is_instance_valid(reanimate_type_button):
		# The SpellReanimate instance itself should handle its type button
		var reanimate_spell = spells[Spell.SpellType.REANIMATE] as SpellReanimate
		if reanimate_spell:
			reanimate_spell.assign_type_button(reanimate_type_button)

	# GameManager reference for spell effects, ensure path is correct or use Autoload
	if not game_manager:
		printerr("Necromancer: GameManager not found!")

	_update_de_calculation() # Initial calculation
	current_de = max_de
	_update_ui()

func _update_de_calculation() -> void:
	max_base_de = int(round(sqrt(2.0 * level) * 5.0) + 10) # Adjusted formula for more DE
	max_de = max_base_de + max_bonus_de

func _update_ui() -> void:
	if is_instance_valid(level_label): level_label.text = "Level: %d" % level
	if is_instance_valid(current_de_label): current_de_label.text = "DE: %d" % current_de
	if is_instance_valid(max_de_label): max_de_label.text = "Max DE: %d" % max_de
	if is_instance_valid(mastery_label): mastery_label.text = "MP: %d" % mastery_points

	var reanimate_spell = spells.get(Spell.SpellType.REANIMATE)
	var soul_drain_spell = spells.get(Spell.SpellType.SOUL_DRAIN)

	if reanimate_spell and is_instance_valid(reanimate_button):
		var cost = reanimate_spell.get_de_cost()
		reanimate_button.text = "REANIMATE L%d (%d DE)" % [reanimate_spell.level, cost]
		reanimate_button.disabled = current_de < cost
	
	if soul_drain_spell and is_instance_valid(soul_drain_button):
		var cost = soul_drain_spell.get_de_cost()
		soul_drain_button.text = "SOUL DRAIN L%d (%d DE)" % [soul_drain_spell.level, cost]
		soul_drain_button.disabled = current_de < cost

	if reanimate_spell and is_instance_valid(reanimate_upgrade_button):
		var cost = reanimate_spell.get_mastery_cost()
		reanimate_upgrade_button.text = "Upgrade (%d MP)" % cost
		reanimate_upgrade_button.disabled = mastery_points < cost
	
	if soul_drain_spell and is_instance_valid(soul_drain_upgrade_button):
		var cost = soul_drain_spell.get_mastery_cost()
		soul_drain_upgrade_button.text = "Upgrade (%d MP)" % cost
		soul_drain_upgrade_button.disabled = mastery_points < cost
	
	# Update reanimate type button text (handled by SpellReanimate instance)
	var r_spell = spells.get(Spell.SpellType.REANIMATE) as SpellReanimate
	if r_spell:
		r_spell.update_type_button_text_if_assigned()


func _on_turn_started(_turn_number: int) -> void:
	current_de = max_de # Full DE replenish at start of turn
	print_debug("Necromancer DE replenished to: ", current_de)
	_update_ui()

# This function is called by GameManager signal when player clicks on a reanimatable corpse
func handle_reanimation_request(dead_creature_info: Dictionary) -> void:
	print_debug("Necromancer received reanimation request for: ", dead_creature_info)
	var spell = spells.get(Spell.SpellType.REANIMATE)
	if spell:
		var cost = spell.get_de_cost()
		if current_de >= cost:
			current_de -= cost
			# The spell's do_effect will call GameManager.reanimate_creature_from_data
			spell.do_effect(self, dead_creature_info) # Pass self (caster) and target data
			# GameManager will handle the actual reanimation & placement
		else:
			_show_not_enough_de_popup("Reanimate")
		_update_ui()
	else:
		push_error("Reanimate spell not found!")

func cast_soul_drain_on_target(target_creature_instance: Creature) -> void: # Example if targeting needed
	var spell = spells.get(Spell.SpellType.SOUL_DRAIN)
	if spell:
		var cost = spell.get_de_cost()
		if current_de >= cost:
			current_de -= cost
			spell.do_effect(self, target_creature_instance) # Target is the creature instance
		else:
			_show_not_enough_de_popup("Soul Drain")
		_update_ui()
	else:
		push_error("Soul Drain spell not found!")


func _show_not_enough_de_popup(spell_name: String) -> void:
	print_debug("Not enough DE to cast %s!" % spell_name)
	# You could instance a small popup UI element here

func _show_not_enough_mastery_popup() -> void:
	print_debug("Not enough Mastery Points to upgrade!")

# --- UI Button Handlers ---
func _on_reanimate_button_pressed() -> void:
	# This button might now just "prime" the reanimate spell,
	# actual casting happens via handle_reanimation_request when a corpse is clicked.
	# Or, if you want it to cast on a pre-selected corpse:
	print("Reanimate button pressed. Select a corpse to reanimate.")
	# For now, this button doesn't directly cast. The selection on grid triggers it.

func _on_soul_drain_pressed() -> void:
	# Soul Drain needs a target. How is it selected?
	# For now, assume it's a global effect or needs specific targeting logic added.
	print("Soul Drain pressed. Targeting logic TBD.")
	# Example: cast_soul_drain_on_target(some_selected_target_creature)
	# If it's an AoE or random target, call spell.do_effect(self, null)
	var spell = spells.get(Spell.SpellType.SOUL_DRAIN)
	if spell:
		var cost = spell.get_de_cost()
		if current_de >= cost:
			current_de -= cost
			spell.do_effect(self, null) # No specific target from button, spell handles targeting
		else:
			_show_not_enough_de_popup("Soul Drain")
		_update_ui()


func _on_level_up_button_pressed() -> void: # Assuming you have a level up button
	level += 1
	mastery_points += 1 # Gain 1 MP per level up
	_update_de_calculation()
	current_de = max_de # Replenish DE on level up as a bonus
	print_debug("Necromancer Leveled Up to %d! MP: %d, Max DE: %d" % [level, mastery_points, max_de])
	_update_ui()

func _on_reanimate_upgrade_pressed() -> void:
	_attempt_spell_level_up(Spell.SpellType.REANIMATE)

func _on_soul_drain_upgrade_pressed() -> void:
	_attempt_spell_level_up(Spell.SpellType.SOUL_DRAIN)

func _attempt_spell_level_up(spell_type: int) -> void:
	var spell = spells.get(spell_type)
	if spell == null:
		push_error("Attempted to upgrade non-existent spell type: %d" % spell_type)
		return

	var cost = spell.get_mastery_cost()
	if mastery_points >= cost:
		mastery_points -= cost
		spell.level_up()
		print_debug("Spell %s upgraded to level %d." % [spell.get_class(), spell.level]) # Spell needs name
		_update_ui()
	else:
		_show_not_enough_mastery_popup()
